import AppKit
import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        @Bindable var store = store  // local binding shadow for `$store` (alert item) under @Observable
        GeometryReader { geometry in
            let compactSidebar = geometry.size.width < 900
            ZStack {
                palette.canvas.ignoresSafeArea()

                HStack(spacing: 0) {
                    SidebarView(compact: compactSidebar)
                        .frame(width: compactSidebar ? 64 : 220)

                    Rectangle()
                        .fill(palette.divider)
                        .frame(width: 1)

                    selectedScreen
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .ignoresSafeArea(.container, edges: .top)
            }
        }
        .tint(palette.activeSignal)
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

    @ViewBuilder
    private var selectedScreen: some View {
        switch store.selectedScreen {
        case .live:
            LiveServiceView()
        case .rehearse:
            RehearseView()
        case .songs:
            SongLibraryView()
        case .pads:
            PadLibraryView()
        }
    }
}

private struct SidebarView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    var compact: Bool

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SustainSpace.sm) {
            BrandHeader(compact: compact)
                .padding(.bottom, SustainSpace.lg)

            if !compact {
                Text("SERVICE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, SustainSpace.sm)
            }

            ForEach(AppScreen.allCases) { screen in
                Button {
                    store.selectedScreen = screen
                } label: {
                    HStack(spacing: SustainSpace.md) {
                        Image(systemName: icon(for: screen))
                            .frame(width: 20)
                        if !compact {
                            Text(screen.rawValue)
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 13, weight: store.selectedScreen == screen ? .semibold : .medium))
                    .foregroundStyle(store.selectedScreen == screen ? palette.activeSignal : palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: compact ? .center : .leading)
                    .padding(.horizontal, compact ? 0 : SustainSpace.sm)
                    .contentShape(Rectangle())
                    .background {
                        if store.selectedScreen == screen {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(palette.activeSignal.opacity(0.12))
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(screen.rawValue)
                .accessibilityLabel(screen.rawValue)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? SustainSpace.sm : SustainSpace.md)
        .padding(.top, SustainLayout.topChrome + SustainSpace.sm)
        .background(palette.sidebar)
    }

    private func icon(for screen: AppScreen) -> String {
        switch screen {
        case .live: "play.circle"
        case .rehearse: "music.quarternote.3"
        case .songs: "music.note.list"
        case .pads: "waveform.badge.plus"
        }
    }
}

private struct BrandHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    var compact = false

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        HStack(spacing: compact ? 0 : SustainSpace.sm) {
            BrandMarkView()
                .frame(width: compact ? 40 : 32, height: compact ? 13 : 10.5)
                .accessibilityHidden(true)
            if !compact {
                Text("SUSTAIN")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(5)
                    .foregroundStyle(palette.activeSignal)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: compact ? .center : .leading)
        .accessibilityLabel("Sustain")
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
