import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        ZStack {
            SustainAppBackground(mood: backgroundMood)

            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView()
            } detail: {
                // Live's detail (a real List + inspector) mounts flush to the window top
                // with no system reserve, so its content rides up under the traffic lights.
                // Reserve the title-bar strip on the detail only (not the whole split view)
                // so the sidebar stays positioned by its own brand header. The other
                // screens keep their system reserve, so this is scoped to Live.
                selectedScreen
                    .padding(.top, store.selectedScreen == .live ? 78 : 0)
            }
            .background(.clear)
        }
        .tint(SustainColor.accent)
        .onAppear { applyAppearance() }
        .onChange(of: appearanceRaw) { applyAppearance() }
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
    }

    /// Pin the whole app to the chosen appearance. `nil` (System) lets it follow the OS
    /// live — reliably, unlike `.preferredColorScheme(nil)`, which sticks on the last choice.
    private func applyAppearance() {
        NSApplication.shared.appearance = (AppAppearance(rawValue: appearanceRaw) ?? .system).nsAppearance
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
    @EnvironmentObject private var store: AppStore

    private var isLive: Bool { store.selectedScreen == .live }

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
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        .safeAreaInset(edge: .top, spacing: 0) {
            BrandHeader()
                .padding(.horizontal, SustainSpace.lg)
                // The Live screen's detail (real List + inspector) makes the split view
                // mount the sidebar flush to the window top, so the brand needs a big top
                // pad to clear the traffic lights. Every other screen leaves the sidebar a
                // large system top reserve instead (see reclaimTopSafeArea below), so a
                // smaller pad lands the brand at the same spot below the controls.
                .padding(.top, isLive ? 96 : 50)
                .padding(.bottom, SustainSpace.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Reclaim the split view's oversized top reserve on the non-Live screens so the
        // brand isn't stranded far below the window controls. Live has no such reserve
        // (it mounts flush), so reclaiming there would pull content up under the controls.
        .reclaimTopSafeArea(!isLive)
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

private extension View {
    /// Conditionally drops the container's top safe area so content can reclaim the
    /// split view's oversized top reserve. A no-op when `active` is false.
    @ViewBuilder
    func reclaimTopSafeArea(_ active: Bool) -> some View {
        if active {
            ignoresSafeArea(.container, edges: .top)
        } else {
            self
        }
    }
}
