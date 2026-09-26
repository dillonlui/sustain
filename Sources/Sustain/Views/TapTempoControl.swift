import SwiftUI

struct TapTempoControl: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var expiryTick = 0
    @State private var isTileHovered = false
    var context: Context
    var presentation: Presentation = .inline

    enum Presentation {
        case inline
        case tile
    }

    enum Context {
        case rehearse
        case live(SetlistEntry.ID)
    }

    private var isAvailable: Bool {
        switch context {
        case .rehearse: store.rehearse.clickState == .off
        case .live(let entryID):
            store.runtime.cuedEntryID == entryID &&
                store.runtime.playingEntryID != entryID &&
                store.runtime.clickState == .off &&
                store.runtime.playbackPhase != .songStarting
        }
    }

    private var estimate: Int? {
        _ = expiryTick
        let now = ProcessInfo.processInfo.systemUptime
        return switch context {
        case .rehearse: store.rehearseTapTempo.bpm(at: now)
        case .live: store.liveTapTempo.bpm(at: now)
        }
    }

    private var tapCount: Int {
        _ = expiryTick
        let now = ProcessInfo.processInfo.systemUptime
        switch context {
        case .rehearse:
            guard let last = store.rehearseTapTempo.lastTap, now - last < 2 else { return 0 }
            return store.rehearseTapTempo.tapCount
        case .live:
            guard let last = store.liveTapTempo.lastTap, now - last < 2 else { return 0 }
            return store.liveTapTempo.tapCount
        }
    }

    private var lastTap: TimeInterval? {
        switch context {
        case .rehearse: store.rehearseTapTempo.lastTap
        case .live: store.liveTapTempo.lastTap
        }
    }

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        Group {
            if presentation == .tile {
                tileContent
            } else {
                inlineContent
            }
        }
        .task(id: lastTap) {
            guard let lastTap else { return }
            let remaining = max(0, 2 - (ProcessInfo.processInfo.systemUptime - lastTap))
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            guard !Task.isCancelled else { return }
            expiryTick &+= 1
        }
    }

    private var tileContent: some View {
        VStack(spacing: 4) {
            Button { store.tapTempo() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 14, weight: .regular))
                    Text("Tap tempo")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(isAvailable ? palette.textPrimary : palette.textSecondary)
                .frame(width: 116, height: 44)
                .background(isTileHovered && isAvailable ? palette.panelElevated : palette.panel,
                            in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(palette.surfaceEdge.opacity(isTileHovered && isAvailable ? 0.9 : 0.55), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(!isAvailable)
            .onHover { isTileHovered = $0 }
            .accessibilityLabel("Tap tempo")
            .accessibilityHint("Tap at least three times, then use the estimated tempo")

            Group {
                if let estimate {
                    Button("Use \(estimate) BPM") { _ = store.useTappedTempo() }
                        .disabled(!isAvailable)
                        .foregroundStyle(palette.activeSignal)
                        .accessibilityLabel("Use estimated tempo, \(estimate) beats per minute")
                } else {
                    Text(tapCount > 0 ? "\(tapCount) of 3 taps" : "Tap 3 times")
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .lineLimit(1)
            .frame(width: 116, height: 20)
        }
        .frame(width: 116, height: 68)
    }

    private var inlineContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Tap tempo") { store.tapTempo() }
                .disabled(!isAvailable)
                .accessibilityHint("Tap at least three times to estimate a tempo")
            if let estimate {
                HStack(spacing: 8) {
                    Text("\(estimate) BPM")
                        .monospacedDigit()
                        .accessibilityLabel("Estimated tempo, \(estimate) beats per minute")
                    Button("Use tempo") { _ = store.useTappedTempo() }
                        .disabled(!isAvailable)
                }
            } else if tapCount > 0 {
                Text("\(tapCount) of 3 taps")
                    .foregroundStyle(.secondary)
            }
            if let message = store.tapTempoMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if case .live(let entryID) = context,
               let bpm = store.liveTempoOverrides[entryID] {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Session tempo: \(bpm) BPM")
                    Button("Save as song default") { _ = store.saveCuedTempoAsSongDefault() }
                        .disabled(!isAvailable)
                }
                .font(.caption)
            }
        }
    }
}
