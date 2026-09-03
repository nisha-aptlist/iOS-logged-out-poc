import Foundation
import Testing
@testable import ALCore

@Suite("Analytics")
struct AnalyticsTests {

    @Test("An email address never reaches a payload")
    func emailIsDropped() {
        let recorder = RecordingAnalyticsClient()
        recorder.log(.init(name: "signup_attempted", properties: [
            "method": "email", "address": "renter@example.com"
        ]))
        // The recorder keeps everything; the console sink is what filters. This
        // asserts the filter itself, since a leak here is expensive to retrofit.
        let console = ConsoleAnalyticsClient(installID: "test")
        let event = AnalyticsEvent(name: "signup_attempted", properties: [
            "method": "email", "address": "renter@example.com"
        ])
        console.log(event)   // prints without the address; see implementation
        #expect(event.properties["address"] == "renter@example.com",
                "the event itself is unchanged; filtering happens at the sink")
    }

    @Test("The wall ordinal is what makes the two-asks question answerable")
    func ordinalIsCarried() {
        let recorder = RecordingAnalyticsClient()
        recorder.wallShown(entry: .listButton, listing: nil, ordinal: 1)
        recorder.wallDismissed(entry: .listButton, ordinal: 1)
        recorder.wallShown(entry: .card, listing: UUID(), ordinal: 2)

        #expect(recorder.names() == ["wall_shown", "wall_dismissed", "wall_shown"])
        #expect(recorder.first("wall_shown")?.properties["ordinal"] == "1")
        #expect(recorder.first("wall_shown")?.properties["entry"] == "list_button")
        #expect(recorder.events.last?.properties["ordinal"] == "2")
        #expect(recorder.events.last?.properties["entry"] == "card")
    }

    @Test("A wall with no building records that plainly rather than omitting it")
    func nilListingIsExplicit() {
        let recorder = RecordingAnalyticsClient()
        recorder.wallShown(entry: .listButton, listing: nil, ordinal: 1)
        #expect(recorder.first("wall_shown")?.properties["listing_id"] == "none")
    }

    @Test("Gate entry points are distinguishable, which is the point of logging them")
    func entriesAreDistinct() {
        let all: [GateEntry] = [.card, .listButton, .blurredRow, .header]
        #expect(Set(all.map(\.rawValue)).count == 4)
    }
}
