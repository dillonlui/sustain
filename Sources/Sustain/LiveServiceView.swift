import SwiftUI

struct LiveServiceView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 18) {
                    ServiceCard(title: "Playing") {
                        SongStatusView(entry: store.playingEntry, emptyTitle: "No Song Playing")
                    }

                    ServiceCard(title: "Cued") {
                        SongStatusView(entry: store.cuedEntry, emptyTitle: "No Song Cued")
                    }
                }
                .frame(minWidth: 360, maxWidth: 420)

                VStack(spacing: 18) {
                    stateGrid
                    primaryControls
                    secondaryControls
                    messageStrip
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.activeSetlist.title)
                    .font(.largeTitle.weight(.semibold))
                Text("Live Service")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            BrandMarkView()
                .frame(width: 116, height: 52)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var stateGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 18) {
            GridRow {
                StateTile(label: "Pad", value: store.runtime.padState.rawValue, systemImage: "waveform")
                StateTile(label: "Click", value: store.runtime.clickState.rawValue, systemImage: "metronome")
            }

            GridRow {
                StateTile(label: "Session", value: store.runtime.playbackPhase.rawValue, systemImage: "dot.radiowaves.left.and.right")
                StateTile(label: "Cue", value: cuePositionText, systemImage: "arrow.forward.circle")
            }
        }
    }

    private var primaryControls: some View {
        HStack(spacing: 12) {
            Button {
                store.startCuedSong()
            } label: {
                Label("Start Song", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                store.cuePreviousSong()
            } label: {
                Label("Previous", systemImage: "backward.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            Button {
                store.cueNextSong()
            } label: {
                Label("Next", systemImage: "forward.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            Button(role: .destructive) {
                store.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
    }

    private var secondaryControls: some View {
        HStack(spacing: 10) {
            Button("Start Click", systemImage: "metronome") {
                store.startClick()
            }

            Button("Stop Click", systemImage: "speaker.slash") {
                store.stopClick()
            }

            Button("Start Pad", systemImage: "waveform") {
                store.startPad()
            }

            Button("Stop Pad", systemImage: "pause.circle") {
                store.stopPad()
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var messageStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.sustainSage)
            Text(store.runtime.lastMessage)
                .font(.callout)
            Spacer()
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var cuePositionText: String {
        guard let cuedID = store.runtime.cuedEntryID,
              let index = store.activeSetlist.entries.firstIndex(where: { $0.id == cuedID }) else {
            return "-"
        }

        return "\(index + 1) of \(store.activeSetlist.entries.count)"
    }
}

private struct SongStatusView: View {
    @EnvironmentObject private var store: AppStore

    var entry: SetlistEntry?
    var emptyTitle: String

    var body: some View {
        if let entry, let song = store.song(for: entry) {
            VStack(alignment: .leading, spacing: 18) {
                Text(song.title)
                    .font(.title.weight(.semibold))

                HStack(spacing: 18) {
                    Metric(label: "Key", value: entry.resolvedKey(for: song).rawValue)
                    Metric(label: "BPM", value: "\(entry.resolvedBPM(for: song))")
                    Metric(label: "Time", value: song.timeSignature.description)
                }

                Text(song.padPack.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(emptyTitle)
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        }
    }
}

private struct ServiceCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct Metric: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(minWidth: 62, alignment: .leading)
    }
}

private struct StateTile: View {
    var label: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.sustainSage)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
            }

            Spacer()
        }
        .padding(18)
        .frame(minWidth: 220, maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}
