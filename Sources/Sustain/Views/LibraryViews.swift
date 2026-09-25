import CoreAudio
import SwiftUI

struct AudioDeviceDiagnosticRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    var output: AudioOutputDevice

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(output.name)
                    .font(.headline)
                Spacer()
                if output.isDefault {
                    Text("Default")
                        .foregroundStyle(palette.textSecondary)
                }
            }

            Text("ID \(output.id) · \(output.diagnosticSummary)")
                .font(.callout)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

struct DiagnosticLine: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    var label: String
    var value: String

    private var palette: FutureSignalColor {
        FutureSignalColor(colorScheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(SustainType.label)
                .foregroundStyle(palette.textSecondary)
                .frame(width: 104, alignment: .leading)

            Text(value)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("Song Library") {
    SongLibraryView()
        .environment(AppStore.preview())
        .frame(width: 940, height: 720)
}
