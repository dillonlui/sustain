import AVFoundation
import Foundation
import Testing
@testable import Sustain

@MainActor
struct ClickSubdivisionTests {
    private func format() throws -> AVAudioFormat {
        try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
    }

    private func peak(_ buffer: AVAudioPCMBuffer, around frame: Int, width: Int = 1_500) throws -> Float {
        let samples = try #require(buffer.floatChannelData?[0])
        let end = min(Int(buffer.frameLength), frame + width)
        return (frame..<end).reduce(Float(0)) { max($0, abs(samples[$1])) }
    }

    @Test func subdivisionGridLeavesBPMBeatsInPlace() throws {
        let format = try format()
        let bpm = 72
        let framesPerBeat = format.sampleRate * 60 / Double(bpm)
        let signature = TimeSignature.fourFour

        for subdivision in ClickSubdivision.allCases {
            let buffer = try SustainAudioEngine.makeClickBuffer(
                format: format,
                bpm: bpm,
                timeSignature: signature,
                subdivision: subdivision,
                measures: 1,
                settings: .default
            )
            #expect(Int(buffer.frameLength) == Int(framesPerBeat * 4))
            for beat in 0..<4 {
                let beatFrame = Int(Double(beat) * framesPerBeat)
                #expect(try peak(buffer, around: beatFrame) > 0.1)
                for slot in 1..<subdivision.rawValue {
                    let frame = Int((Double(beat) + Double(slot) / Double(subdivision.rawValue)) * framesPerBeat)
                    #expect(try peak(buffer, around: frame) > 0.05)
                }
            }
            if subdivision == .beat {
                #expect(try peak(buffer, around: Int(framesPerBeat / 2)) == 0)
            }
        }
    }

    @Test func everySupportedMeterAndSampleRateHasExpectedGrid() throws {
        for sampleRate in [44_100.0, 48_000.0] {
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2))
            for bpm in [40, 72, 220] {
                let framesPerBeat = sampleRate * 60 / Double(bpm)
                for signature in TimeSignature.common {
                    for subdivision in ClickSubdivision.allCases {
                        let buffer = try SustainAudioEngine.makeClickBuffer(
                            format: format, bpm: bpm, timeSignature: signature,
                            subdivision: subdivision, measures: 1, settings: .default
                        )
                        #expect(Int(buffer.frameLength) == Int(framesPerBeat * Double(signature.beatsPerMeasure)))
                        for beat in 0..<signature.beatsPerMeasure {
                            for slot in 0..<subdivision.rawValue {
                                let frame = Int((Double(beat) + Double(slot) / Double(subdivision.rawValue)) * framesPerBeat)
                                #expect(try peak(buffer, around: frame, width: 500) > 0.05)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func countoffOnlySubdividesClickOnlyMode() throws {
        let format = try format()
        let settings = ClickSettings(accentMode: .downbeat, countoffSound: .counted)
        let counted = try SustainAudioEngine.makeCountoffBuffer(
            format: format, voiceRenderer: nil, bpm: 72, timeSignature: .fourFour,
            subdivision: .two, settings: settings
        )
        let framesPerBeat = Int(format.sampleRate * 60 / 72)
        #expect(try peak(counted, around: framesPerBeat / 2) == 0)

        var clickSettings = settings
        clickSettings.countoffSound = .click
        let clicks = try SustainAudioEngine.makeCountoffBuffer(
            format: format, voiceRenderer: nil, bpm: 72, timeSignature: .fourFour,
            subdivision: .two, settings: clickSettings
        )
        #expect(try peak(clicks, around: framesPerBeat / 2) > 0.05)
    }

    @Test func rendererAppliesNewPatternAtExactMeasureBoundary() throws {
        let format = try format()
        let first = try SustainAudioEngine.makeClickBuffer(
            format: format, bpm: 72, timeSignature: .fourFour, subdivision: .beat,
            measures: 1, settings: .default
        )
        let second = try SustainAudioEngine.makeClickBuffer(
            format: format, bpm: 72, timeSignature: .fourFour, subdivision: .two,
            measures: 1, settings: .default
        )
        let renderer = ClickLoopRenderer(format: format)
        try renderer.start(PreparedClick(loop: ImmutablePCMBuffer(buffer: first, byteCount: 0), countoff: nil))
        try renderer.queue(PreparedClick(loop: ImmutablePCMBuffer(buffer: second, byteCount: 0), countoff: nil), serial: 1)

        let output = try #require(AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: first.frameLength + second.frameLength
        ))
        output.frameLength = output.frameCapacity
        #expect(renderer.render(frameCount: output.frameLength, audioBufferList: output.mutableAudioBufferList) == noErr)
        #expect(renderer.lastAppliedSerial == 1)
        let halfBeat = Int(format.sampleRate * 60 / 72 / 2)
        #expect(try peak(output, around: halfBeat) == 0)
        #expect(try peak(output, around: Int(first.frameLength)) > 0.1)
        #expect(try peak(output, around: Int(first.frameLength) + halfBeat) > 0.05)
    }

    @Test func oldLibrariesDefaultToBeatAndNewSchemaRequiresField() throws {
        let snapshot = AppStore.seedSnapshot()
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        var songs = try #require(object["songs"] as? [[String: Any]])
        for index in songs.indices { songs[index].removeValue(forKey: "clickSubdivision") }
        object["songs"] = songs
        object["schemaVersion"] = 3
        let old = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.songs.allSatisfy { $0.clickSubdivision == .beat })
        object["schemaVersion"] = 4
        #expect(throws: Error.self) {
            _ = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test func liveAndRehearseSelectionsStayIndependent() throws {
        let audio = RecordingAudioEngine()
        let store = AppStore.preview(audioEngine: audio)
        let songID = try #require(store.songs.first?.id)
        #expect(store.setSongClickSubdivision(songID, subdivision: .three))
        #expect(store.songs.first?.clickSubdivision == .three)
        store.rehearse.countoffEnabled = false
        store.startRehearseClick()
        store.setRehearseClickSubdivision(.four)
        #expect(store.rehearse.clickSubdivision == .four)
        #expect(store.songs.first?.clickSubdivision == .three)
    }

    @Test func liveChangeCommitsOnlyAfterAudibleBoundary() throws {
        let audio = RecordingAudioEngine()
        audio.defersClickSwitch = true
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedSong()
        store.runtime.clickState = .playing
        let songID = try #require(store.playingEntry?.songID)

        #expect(store.setSongClickSubdivision(songID, subdivision: .three))
        #expect(store.pendingClickSubdivision(for: songID) == .three)
        #expect(store.songs.first { $0.id == songID }?.clickSubdivision == .beat)
        #expect(store.audibleClickSubdivision == .beat)

        audio.completePendingClickSwitch()
        #expect(store.pendingClickSubdivision(for: songID) == nil)
        #expect(store.songs.first { $0.id == songID }?.clickSubdivision == .three)
        #expect(store.audibleClickSubdivision == .three)
    }

    @Test func rapidRehearseChangesReportIntermediateAudibleMode() {
        let audio = RecordingAudioEngine()
        audio.defersClickSwitch = true
        let store = AppStore.preview(audioEngine: audio)
        store.rehearse.countoffEnabled = false
        store.startRehearseClick()

        store.setRehearseClickSubdivision(.two)
        store.setRehearseClickSubdivision(.four)
        #expect(store.pendingRehearseClickSubdivision == .four)
        audio.completePendingClickSwitch()
        #expect(store.audibleClickSubdivision == .two)
        #expect(store.rehearse.clickSubdivision == .beat)
        audio.completePendingClickSwitch()
        #expect(store.audibleClickSubdivision == .four)
        #expect(store.rehearse.clickSubdivision == .four)
        #expect(store.pendingRehearseClickSubdivision == nil)
    }

    @Test func stoppingCancelsPendingChangeWithoutChangingSongDefault() throws {
        let audio = RecordingAudioEngine()
        audio.defersClickSwitch = true
        let store = AppStore.preview(audioEngine: audio)
        store.startCuedSong()
        store.runtime.clickState = .playing
        let songID = try #require(store.playingEntry?.songID)
        store.setSongClickSubdivision(songID, subdivision: .four)
        store.stop()
        audio.completePendingClickSwitch()
        #expect(store.pendingClickSubdivision(for: songID) == nil)
        #expect(store.songs.first { $0.id == songID }?.clickSubdivision == .beat)
        #expect(store.audibleClickSubdivision == nil)
    }
}
