import AppKit
import Foundation
import Observation
import Security
import Sparkle

enum UpdateBuildEligibility: Equatable, Sendable {
    case eligible
    case ineligible(String)

    var isEligible: Bool {
        if case .eligible = self { return true }
        return false
    }

    static func evaluate(
        info: [String: Any],
        hasValidDeveloperIDSignature: Bool
    ) -> UpdateBuildEligibility {
        guard info["SustainOfficialStableUpdatesEnabled"] as? Bool == true else {
            return .ineligible("This is not an official stable update build.")
        }
        guard hasValidDeveloperIDSignature else {
            return .ineligible("The app is not signed with a valid Developer ID identity.")
        }
        guard let version = info["CFBundleShortVersionString"] as? String,
              version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil else {
            return .ineligible("The release version is not a stable semantic version.")
        }
        guard let build = info["CFBundleVersion"] as? String,
              !build.isEmpty,
              build.allSatisfy(\.isNumber),
              build.first != "0" else {
            return .ineligible("The release build number is invalid.")
        }
        guard let feed = info["SUFeedURL"] as? String,
              let feedURL = URL(string: feed),
              feedURL.scheme?.lowercased() == "https",
              feedURL.host != nil else {
            return .ineligible("The stable update feed is missing or is not HTTPS.")
        }
        guard let publicKey = info["SUPublicEDKey"] as? String,
              !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .ineligible("The update verification key is missing.")
        }
        return .eligible
    }
}

struct DeveloperIDSignatureInspector {
    static func isValidDeveloperIDApplication(at bundleURL: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode,
              SecStaticCodeCheckValidity(
                staticCode,
                SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
                nil
              ) == errSecSuccess else {
            return false
        }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &signingInformation) == errSecSuccess,
              let information = signingInformation as? [CFString: Any],
              let certificates = information[kSecCodeInfoCertificates] as? [SecCertificate],
              let leaf = certificates.first,
              let subject = SecCertificateCopySubjectSummary(leaf) as String? else {
            return false
        }
        return subject.hasPrefix("Developer ID Application:")
    }
}

@MainActor
protocol UpdateChecking: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    func checkForUpdates()
    func checkForUpdatesInBackground()
}

@MainActor
private final class SparkleUpdateDriver: UpdateChecking {
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() { updater.checkForUpdates() }
    func checkForUpdatesInBackground() { updater.checkForUpdatesInBackground() }
}

enum UpdateCheckKind: Equatable, Sendable {
    case manual
    case background
}

@Observable
@MainActor
final class UpdateCoordinator: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private(set) var eligibility: UpdateBuildEligibility
    private(set) var statusMessage: String?
    private(set) var hasDeferredCheck = false
    private(set) var hasDeferredRelaunch = false

    private let bundleURL: URL
    private let isAudioActive: () -> Bool
    private let flushPersistence: () -> Bool
    private let statusSink: (String) -> Void
    private let isReadOnlyVolume: (URL) -> Bool
    private var controller: SPUStandardUpdaterController?
    private var driver: UpdateChecking?
    private var pendingInstallHandler: (() -> Void)?
    private var started = false

    init(
        bundle: Bundle = .main,
        hasValidDeveloperIDSignature: Bool? = nil,
        isAudioActive: @escaping () -> Bool,
        flushPersistence: @escaping () -> Bool,
        statusSink: @escaping (String) -> Void,
        isReadOnlyVolume: @escaping (URL) -> Bool = UpdateCoordinator.bundleIsOnReadOnlyVolume
    ) {
        bundleURL = bundle.bundleURL
        eligibility = .evaluate(
            info: bundle.infoDictionary ?? [:],
            hasValidDeveloperIDSignature: hasValidDeveloperIDSignature ??
                DeveloperIDSignatureInspector.isValidDeveloperIDApplication(at: bundle.bundleURL)
        )
        self.isAudioActive = isAudioActive
        self.flushPersistence = flushPersistence
        self.statusSink = statusSink
        self.isReadOnlyVolume = isReadOnlyVolume
        super.init()
    }

    init(
        eligibility: UpdateBuildEligibility,
        driver: UpdateChecking,
        bundleURL: URL = URL(fileURLWithPath: "/Applications/Sustain.app"),
        isAudioActive: @escaping () -> Bool,
        flushPersistence: @escaping () -> Bool,
        statusSink: @escaping (String) -> Void = { _ in },
        isReadOnlyVolume: @escaping (URL) -> Bool = { _ in false }
    ) {
        self.eligibility = eligibility
        self.driver = driver
        self.bundleURL = bundleURL
        self.isAudioActive = isAudioActive
        self.flushPersistence = flushPersistence
        self.statusSink = statusSink
        self.isReadOnlyVolume = isReadOnlyVolume
        super.init()
    }

    var isEligible: Bool { eligibility.isEligible }

    var automaticallyChecksForUpdates: Bool {
        get { driver?.automaticallyChecksForUpdates ?? false }
        set {
            guard isEligible else { return }
            driver?.automaticallyChecksForUpdates = newValue
        }
    }

    /// Called after app launch. Ineligible builds never instantiate Sparkle and therefore
    /// cannot contact an appcast even if a malformed development plist contains feed keys.
    func startIfEligible() {
        guard isEligible, !started else { return }
        started = true
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        self.controller = controller
        driver = SparkleUpdateDriver(updater: controller.updater)
        controller.startUpdater()
    }

    func requestManualCheck() {
        guard isEligible else { return }
        guard !isReadOnlyVolume(bundleURL) else {
            publish("Install Sustain in Applications before checking for updates")
            let alert = NSAlert()
            alert.messageText = "Move Sustain to Applications"
            alert.informativeText = "Quit Sustain, drag it to Applications, eject the disk image, then reopen the installed copy before checking for updates."
            alert.alertStyle = .informational
            alert.runModal()
            return
        }
        guard !isAudioActive() else {
            deferCheck()
            publish("Update check deferred until playback stops")
            return
        }
        statusMessage = nil
        driver?.checkForUpdates()
    }

    func audioActivityDidChange() {
        guard !isAudioActive() else { return }
        releaseDeferredCheckIfPossible()
        releaseDeferredRelaunchIfPossible()
    }

    func persistenceDidRecover() {
        releaseDeferredRelaunchIfPossible()
    }

    func allowCheck(_ kind: UpdateCheckKind) throws {
        guard isEligible else {
            throw updateError("Updates are unavailable in this build.")
        }
        guard !isReadOnlyVolume(bundleURL) else {
            if kind == .background { deferCheck() }
            throw updateError("Install Sustain in Applications before checking for updates.")
        }
        guard !isAudioActive() else {
            deferCheck()
            throw updateError("Update check deferred until playback stops.")
        }
    }

    func postponeRelaunch(untilInvoking installHandler: @escaping () -> Void) -> Bool {
        if isAudioActive() {
            pendingInstallHandler = installHandler
            hasDeferredRelaunch = true
            publish("Update will finish after playback stops")
            return true
        }
        guard flushPersistence() else {
            pendingInstallHandler = installHandler
            hasDeferredRelaunch = true
            publish("Update waiting for the library to save")
            return true
        }
        return false
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        try allowCheck(updateCheck == .updates ? .manual : .background)
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        postponeRelaunch(untilInvoking: installHandler)
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        finishUpdateCycle(
            kind: updateCheck == .updates ? .manual : .background,
            error: error
        )
    }

    func finishUpdateCycle(kind: UpdateCheckKind, error: (any Error)?) {
        guard kind == .manual, let error else { return }
        statusMessage = error.localizedDescription
    }

    private func deferCheck() {
        hasDeferredCheck = true
    }

    private func releaseDeferredCheckIfPossible() {
        guard hasDeferredCheck, isEligible, !isReadOnlyVolume(bundleURL) else { return }
        hasDeferredCheck = false
        publish("Checking for updates")
        driver?.checkForUpdatesInBackground()
    }

    private func releaseDeferredRelaunchIfPossible() {
        guard let handler = pendingInstallHandler, !isAudioActive() else { return }
        guard flushPersistence() else {
            publish("Update waiting for the library to save")
            return
        }
        pendingInstallHandler = nil
        hasDeferredRelaunch = false
        statusMessage = nil
        handler()
    }

    private func publish(_ message: String) {
        statusMessage = message
        statusSink(message)
    }

    private func updateError(_ message: String) -> NSError {
        NSError(
            domain: "com.sustain.app.updates",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    nonisolated static func bundleIsOnReadOnlyVolume(_ bundleURL: URL) -> Bool {
        (try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true
    }
}
