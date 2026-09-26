import Foundation

/// Editable song fields. A new draft has no ID until Save commits it to the library.
struct SongDraft: Equatable {
    var id: Song.ID?
    var title: String
    var padTrackID: PadTrack.ID?
    var defaultBPM: Int
    var timeSignature: TimeSignature
    var clickSubdivision: ClickSubdivision
    var pulseInterpretation: PulseInterpretation
    var clickAccentPattern: [ClickAccentLevel]?
    var countoffPolicy: CountoffPolicy

    init(song: Song) {
        id = song.id
        title = song.title
        padTrackID = song.padTrackID
        defaultBPM = song.defaultBPM
        timeSignature = song.timeSignature
        clickSubdivision = song.clickSubdivision
        pulseInterpretation = song.pulseInterpretation
        clickAccentPattern = song.clickAccentPattern
        countoffPolicy = song.countoffPolicy
    }

    static func newSong() -> SongDraft {
        SongDraft(
            id: nil,
            title: "",
            padTrackID: PadTrack.includedID(for: .c),
            defaultBPM: 72,
            timeSignature: .fourFour,
            clickSubdivision: .beat,
            pulseInterpretation: .legacy,
            clickAccentPattern: nil,
            countoffPolicy: .liveDefault
        )
    }

    private init(
        id: Song.ID?,
        title: String,
        padTrackID: PadTrack.ID?,
        defaultBPM: Int,
        timeSignature: TimeSignature,
        clickSubdivision: ClickSubdivision,
        pulseInterpretation: PulseInterpretation,
        clickAccentPattern: [ClickAccentLevel]?,
        countoffPolicy: CountoffPolicy
    ) {
        self.id = id
        self.title = title
        self.padTrackID = padTrackID
        self.defaultBPM = defaultBPM
        self.timeSignature = timeSignature
        self.clickSubdivision = clickSubdivision
        self.pulseInterpretation = pulseInterpretation
        self.clickAccentPattern = clickAccentPattern
        self.countoffPolicy = countoffPolicy
    }
}
