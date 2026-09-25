import Foundation

/// Editable song fields. A new draft has no ID until Save commits it to the library.
struct SongDraft: Equatable {
    var id: Song.ID?
    var title: String
    var padTrackID: PadTrack.ID?
    var defaultBPM: Int
    var timeSignature: TimeSignature
    var clickSubdivision: ClickSubdivision

    init(song: Song) {
        id = song.id
        title = song.title
        padTrackID = song.padTrackID
        defaultBPM = song.defaultBPM
        timeSignature = song.timeSignature
        clickSubdivision = song.clickSubdivision
    }

    static func newSong() -> SongDraft {
        SongDraft(
            id: nil,
            title: "",
            padTrackID: PadTrack.includedID(for: .c),
            defaultBPM: 72,
            timeSignature: .fourFour,
            clickSubdivision: .beat
        )
    }

    private init(
        id: Song.ID?,
        title: String,
        padTrackID: PadTrack.ID?,
        defaultBPM: Int,
        timeSignature: TimeSignature,
        clickSubdivision: ClickSubdivision
    ) {
        self.id = id
        self.title = title
        self.padTrackID = padTrackID
        self.defaultBPM = defaultBPM
        self.timeSignature = timeSignature
        self.clickSubdivision = clickSubdivision
    }
}
