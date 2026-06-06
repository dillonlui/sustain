import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            switch store.selectedScreen {
            case .live:
                LiveServiceView()
            case .songs:
                SongLibraryView()
            case .setlist:
                SetlistBuilderView()
            case .audio:
                AudioSetupView()
            case .check:
                SystemCheckView()
            }
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        List(selection: $store.selectedScreen) {
            Section {
                BrandHeader()
                    .padding(.vertical, 8)
            }

            Section("Service") {
                ForEach(AppScreen.allCases) { screen in
                    Label(screen.rawValue, systemImage: icon(for: screen))
                        .tag(screen)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 240)
    }

    private func icon(for screen: AppScreen) -> String {
        switch screen {
        case .live: "play.circle"
        case .songs: "music.note.list"
        case .setlist: "list.bullet"
        case .audio: "speaker.wave.2"
        case .check: "checkmark.shield"
        }
    }
}

private struct BrandHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BrandMarkView()
                .frame(width: 92, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("SUSTAIN")
                    .font(.system(.title3, design: .default, weight: .semibold))
                    .tracking(6)
                Text("Atmosphere. Presence. Flow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
