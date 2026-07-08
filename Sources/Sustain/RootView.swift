import AppKit
import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    /// Reserved strip at the very top of the window, under `.hiddenTitleBar`, so content clears
    /// the traffic-light controls and leaves a draggable title-bar zone. We OWN this inset — it
    /// is a single fixed value, so unlike `NavigationSplitView` it cannot flip between mount
    /// modes when state changes mid-service (the root cause fixed here; see docs/13).
    private static let topChrome: CGFloat = 28

    var body: some View {
        @Bindable var store = store  // local binding shadow for `$store` (alert item) under @Observable
        ZStack {
            SustainAppBackground(mood: backgroundMood)

            HStack(spacing: 0) {
                SidebarView(topChrome: Self.topChrome)
                    .frame(width: 220)

                Divider()

                selectedScreen
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, Self.topChrome)
            }
        }
        .tint(SustainColor.accent)
        .onAppear { applyAppearance() }
        .onChange(of: appearanceRaw) { applyAppearance() }
        // Last-chance flush of unsaved work when the app leaves the foreground (a backstop for
        // the rare case a prior save failed; normal edits already persist eagerly).
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flushPendingSaveIfNeeded() }
        }
        .alert(item: $store.audioRouteChangePrompt) { prompt in
            Alert(
                title: Text("Audio Output Change Detected"),
                message: Text(prompt.message),
                primaryButton: .default(Text("Keep Current Settings")) {
                    store.keepCurrentAudioRouting()
                },
                secondaryButton: .default(Text("Switch to \(prompt.detectedOutputName)")) {
                    store.switchToDetectedAudioOutput()
                }
            )
        }
        .alert(item: $store.saveErrorPrompt) { prompt in
            Alert(
                title: Text("Couldn't Save Library"),
                message: Text(prompt.message),
                primaryButton: .default(Text("Try Again")) {
                    store.retryFailedSave()
                },
                secondaryButton: .cancel(Text("Dismiss"))
            )
        }
    }

    /// Pin the whole app to the chosen appearance. `nil` (System) lets it follow the OS
    /// live — reliably, unlike `.preferredColorScheme(nil)`, which sticks on the last choice.
    private func applyAppearance() {
        let appearance = (AppAppearance(rawValue: appearanceRaw) ?? .system).nsAppearance
        NSApplication.shared.appearance = appearance
        // Push onto every open window too: setting only the app appearance leaves
        // background windows' AppKit-backed controls (e.g. the menu-style Picker /
        // NSPopUpButton) stale until the window is next focused. Assigning the window
        // appearance forces an immediate effective-appearance refresh of their subviews.
        for window in NSApplication.shared.windows {
            window.appearance = appearance
        }
    }

    private var backgroundMood: SustainBackgroundMood {
        switch store.selectedScreen {
        case .live:
            return .live
        case .rehearse:
            return .rehearse
        case .songs:
            return .standard
        }
    }

    @ViewBuilder
    private var selectedScreen: some View {
        switch store.selectedScreen {
        case .live:
            LiveServiceView()
        case .rehearse:
            RehearseView()
        case .songs:
            SongLibraryView()
        }
    }
}

private struct SidebarView: View {
    @Environment(AppStore.self) private var store

    /// Top reserve so the brand clears the window's traffic-light controls (the sidebar runs
    /// full-height to the window top under `.hiddenTitleBar`).
    let topChrome: CGFloat

    var body: some View {
        List(selection: selectionBinding) {
            Section("Service") {
                ForEach(AppScreen.allCases) { screen in
                    Label(screen.rawValue, systemImage: icon(for: screen))
                        .tag(screen)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            BrandHeader()
                .padding(.horizontal, SustainSpace.lg)
                .padding(.top, topChrome + SustainSpace.sm)
                .padding(.bottom, SustainSpace.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectionBinding: Binding<AppScreen?> {
        Binding {
            store.selectedScreen
        } set: { newValue in
            if let newValue {
                store.selectedScreen = newValue
            }
        }
    }

    private func icon(for screen: AppScreen) -> String {
        switch screen {
        case .live: "play.circle"
        case .rehearse: "music.quarternote.3"
        case .songs: "music.note.list"
        }
    }
}

private struct BrandHeader: View {
    var body: some View {
        HStack(spacing: SustainSpace.sm) {
            BrandMarkView()
                .frame(width: 34, height: 20)
            Text("SUSTAIN")
                .font(.headline)
                .tracking(3)
        }
    }
}

#Preview("App shell – idle") {
    RootView()
        .environment(AppStore.preview())
        .frame(width: 1200, height: 760)
}

#Preview("App shell – playing") {
    let store = AppStore.preview()
    store.startCuedSong()
    return RootView()
        .environment(store)
        .frame(width: 1200, height: 760)
}
