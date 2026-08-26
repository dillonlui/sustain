import AVFoundation
import Foundation
import Testing
@testable import Sustain

private func testPCM(byteCount: UInt64) -> ImmutablePCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
    buffer.frameLength = 1
    return ImmutablePCMBuffer(buffer: buffer, byteCount: byteCount)
}

private func testBufferKey(_ value: UInt8) -> PadBufferKey {
    PadBufferKey(
        padID: UUID(),
        resourceIdentityData: Data([value]),
        fingerprint: ExternalFileFingerprint(
            resourceIdentifierData: Data([value]),
            fileSize: Int64(value),
            modificationDate: nil
        )
    )
}

private final class LockedDecodeResults: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func append(_ value: String) { lock.withLock { values.append(value) } }
    var snapshot: [String] { lock.withLock { values } }
}

@Suite("Prepared audio contract")
struct PreparedAudioTests {
    @Test func byteStoreEvictsOnlyInactiveLRUAndRejectsPinnedOvercommit() throws {
        let store = PadBufferMemoryStore(singlePadLimit: 300, totalBudget: 500)
        let first = testBufferKey(1)
        let second = testBufferKey(2)
        let third = testBufferKey(3)
        try store.admitAndRetain(testPCM(byteCount: 200), for: first)
        store.release(first)
        try store.admitAndRetain(testPCM(byteCount: 200), for: second)
        try store.admitAndRetain(testPCM(byteCount: 200), for: third)
        #expect(store.totalBytes == 400)
        #expect(store.pinnedBytes == 400)

        let pinned = PadBufferMemoryStore(singlePadLimit: 400, totalBudget: 500)
        try pinned.admitAndRetain(testPCM(byteCount: 300), for: first)
        #expect(throws: PadMemoryError.self) {
            try pinned.admitAndRetain(testPCM(byteCount: 250), for: second)
        }
        pinned.evictInactive()
        #expect(pinned.totalBytes == 300)
    }

    @Test func latestWinsDecoderKeepsOneActiveAndNewestPending() async {
        let decoder = LatestWinsPadDecoder()
        let results = LockedDecodeResults()
        let first = testBufferKey(1)
        let obsolete = testBufferKey(2)
        let newest = testBufferKey(3)

        decoder.submit(key: first, operation: {
            try await Task.sleep(for: .milliseconds(40))
            return testPCM(byteCount: 1)
        }) { result in results.append(result.isSuccess ? "first" : "first-failed") }
        decoder.submit(key: obsolete, operation: { testPCM(byteCount: 1) }) { result in
            results.append(result.isSuccess ? "obsolete" : "obsolete-cancelled")
        }
        decoder.submit(key: newest, operation: { testPCM(byteCount: 1) }) { result in
            results.append(result.isSuccess ? "newest" : "newest-failed")
        }

        try? await Task.sleep(for: .milliseconds(100))
        #expect(results.snapshot.contains("first"))
        #expect(results.snapshot.contains("obsolete-cancelled"))
        #expect(results.snapshot.contains("newest"))
        #expect(!results.snapshot.contains("obsolete"))
    }

    @Test @MainActor func appStoreUsesPrepareThenActivateAndNoPadSkipsPad() throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        let prepareBefore = audio.padPrepareCount
        store.startCuedSong()
        #expect(audio.padPrepareCount == prepareBefore + 1)
        #expect(audio.padActivateCount == 1)
        #expect(store.runtime.audiblePadTrackID != nil)

        store.stop()
        let secondEntry = store.activeSetlist.entries[1]
        let secondSong = try #require(store.song(for: secondEntry))
        #expect(store.setSongPadTrackID(secondSong.id, padTrackID: nil))
        store.cue(entryID: secondEntry.id)
        let activations = audio.padActivateCount
        store.startCuedSong()
        #expect(store.runtime.playingEntryID == secondEntry.id)
        #expect(store.runtime.padState == .fadingOut)
        #expect(store.runtime.audiblePadTrackID != nil)
        #expect(audio.padActivateCount == activations)
        #expect(audio.isClickActive)
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
