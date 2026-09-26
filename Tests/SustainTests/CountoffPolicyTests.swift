import Foundation
import Testing
@testable import Sustain

@Suite struct CountoffPolicyTests {
    @Test func defaultsMatchExistingLiveStart() {
        #expect(CountoffPolicy.liveDefault.bars == 1)
        #expect(CountoffPolicy.liveDefault.after == .continueClick)
    }

    @Test func invalidPersistedCombinationsAreRejected() throws {
        for json in [
            #"{"bars":-1,"after":"continueClick"}"#,
            #"{"bars":3,"after":"continueClick"}"#,
            #"{"bars":0,"after":"countoffOnly"}"#
        ] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(CountoffPolicy.self, from: Data(json.utf8))
            }
        }
    }
}
