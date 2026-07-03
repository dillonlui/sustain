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
                selectedScreen
            }
            .background(.clear)
        }
        .tint(SustainColor.accent)
        .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .system).colorScheme)
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

    private var backgroundMood: SustainBackgroundMood {
        switch store.selectedScreen {
        case .live:
            return .live
        case .rehearse:
            return .rehearse
        case .songs:
            return .standard
        case .audio:
            return .audio
        case .check:
            return .system
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
        case .audio:
            AudioSetupView()
        case .check:
            SystemCheckView()
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var store: AppStore

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
                .padding(.top, SustainSpace.md)
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
        case .audio: "speaker.wave.2"
        case .check: "checkmark.shield"
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
