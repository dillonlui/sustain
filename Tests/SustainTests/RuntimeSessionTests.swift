import Testing
@testable import Sustain

@MainActor
struct RuntimeSessionTests {
    @Test func nextSongOnlyChangesCue() {
        let store = AppStore.preview()
        store.startCuedSong()

        let playing = store.runtime.playingEntryID
        store.cueNextSong()

        #expect(store.runtime.playingEntryID == playing)
        #expect(store.runtime.cuedEntryID != playing)
    }

    @Test func startClickAlwaysUsesCountoffBeforePlaying() {
        let store = AppStore.preview()
        store.startCuedSong()
        store.stopClick()

        store.startClick()

        #expect(store.runtime.clickState == .playing)
        #expect(store.runtime.lastMessage == "Click started after countoff")
    }

    @Test func invalidTransitionDoesNotDestroyPlayingState() {
        let store = AppStore.preview()
        store.startCuedSong()
        let playing = store.runtime.playingEntryID

        store.cueNextSong()
        store.cueNextSong()
        store.startCuedSong()

        #expect(store.runtime.playingEntryID == playing)
        #expect(store.runtime.lastMessage == "Playback blocked by system check")
    }
}
