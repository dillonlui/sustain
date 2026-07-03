import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

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
        VStack(alignment: .leading, spacing: SustainSpace.xl) {
            BrandHeader()
                .padding(.top, SustainSpace.xl)

            VStack(alignment: .leading, spacing: SustainSpace.sm) {
                Text("Service")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, SustainSpace.sm)

                ForEach(AppScreen.allCases) { screen in
                    SidebarRow(
                        title: screen.rawValue,
                        systemImage: icon(for: screen),
                        isSelected: store.selectedScreen == screen
                    ) {
                        withAnimation(.smooth(duration: 0.2)) {
                            store.selectedScreen = screen
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, SustainSpace.lg)
        .padding(.vertical, SustainSpace.lg)
        .navigationSplitViewColumnWidth(min: 220, ideal: 240)
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
        VStack(alignment: .leading, spacing: 10) {
            BrandMarkView()
                .frame(width: 92, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("SUSTAIN")
                    .font(.system(.title3, design: .default, weight: .semibold))
                    .tracking(6)
                Text("Atmosphere. Presence. Flow.")
                    .font(.caption)
                    .foregroundStyle(SustainColor.textSecondary)
            }
        }
    }
}

private struct SidebarRow: View {
    var title: String
    var systemImage: String
    var isSelected: Bool
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SustainSpace.md) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.semibold))
                    .frame(width: 20)
                Text(title)
                    .font(.callout.weight(.medium))
                Spacer()
            }
            .foregroundStyle(isSelected ? Color.sustainNearBlack : SustainColor.textSecondary)
            .padding(.horizontal, SustainSpace.md)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: SustainRadius.control, style: .continuous)
                    .fill(rowFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SustainRadius.control, style: .continuous)
                    .stroke(rowStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.smooth(duration: 0.16), value: isHovering)
        .animation(.smooth(duration: 0.2), value: isSelected)
    }

    private var rowFill: Color {
        if isSelected {
            return SustainColor.accent.opacity(0.88)
        }
        return SustainColor.accent.opacity(isHovering ? 0.13 : 0.04)
    }

    private var rowStroke: Color {
        if isSelected {
            return Color.sustainIvory.opacity(0.32)
        }
        return SustainColor.accent.opacity(isHovering ? 0.24 : 0.08)
    }
}
