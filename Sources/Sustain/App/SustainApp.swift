import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The AppKit appearance to pin the app to. `nil` (System) lets the window follow the
    /// OS setting live. We drive `NSApplication.appearance` with this instead of relying on
    /// SwiftUI's `.preferredColorScheme`, which on macOS fails to clear a previously pinned
    /// appearance when returning to System — leaving it stuck on the last Light/Dark choice.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@main
struct SustainApp: App {
    @State private var store = AppStore.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .frame(minWidth: 1200, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            SustainCommands(store: store)
        }

        Settings {
            AppSettingsView()
                .environment(store)
        }
    }
}

/// Menu-bar commands for live performance: transport (start/prev/next/stop,
/// click, pad) and screen navigation, all reachable from any screen and shown
/// with their keyboard shortcuts so performers can discover them.
struct SustainCommands: Commands {
    var store: AppStore

    private var isTransition: Bool {
        store.runtime.playingEntryID != nil &&
            store.runtime.cuedEntryID != store.runtime.playingEntryID
    }

    var body: some Commands {
        CommandMenu("Performance") {
            Button(isTransition ? "Transition" : "Start") {
                store.startCuedSong()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(store.cuedEntry == nil || store.isCuedSongPlaying)

            Button("Previous Song") {
                store.cuePreviousSong()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(store.activeSetlist.entries.isEmpty)

            Button("Next Song") {
                store.cueNextSong()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(store.activeSetlist.entries.isEmpty)

            Button("Stop") {
                store.stop()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(store.runtime.playbackPhase == .noSongPlaying)

            Divider()

            Button(store.runtime.clickState == .off ? "Start Click" : "Stop Click") {
                store.runtime.clickState == .off ? store.startClick() : store.stopClick()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(store.runtime.playbackPhase == .noSongPlaying)

            Button(store.runtime.padState == .off ? "Start Pad" : "Stop Pad") {
                store.runtime.padState == .off ? store.startPad() : store.stopPad()
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(store.runtime.playbackPhase == .noSongPlaying)
        }

        CommandMenu("Go") {
            ForEach(Array(AppScreen.allCases.enumerated()), id: \.element.id) { index, screen in
                Button(screen.rawValue) {
                    store.selectedScreen = screen
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}

struct AppSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            AudioSettingsView()
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
        }
    }
}

private struct GeneralSettingsView: View {
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("About") {
                LabeledContent("Version", value: Self.appVersion)
                VStack(alignment: .leading, spacing: SustainSpace.xs) {
                    Text("Pad audio")
                        .font(.callout)
                    Text("“Ambient Pad Bases” by Karl Verkade — ambient guitar pads in all 12 keys, included with gratitude and offered free for church use.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link("Support the artist on Bandcamp",
                         destination: URL(string: "https://karlverkade.bandcamp.com/album/ambient-pad-bases")!)
                        .font(.footnote)
                }
                .padding(.vertical, SustainSpace.xxs)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 300)
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}
