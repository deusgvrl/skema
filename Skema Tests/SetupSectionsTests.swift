import Testing
import Foundation
@testable import Final_Challenge_App

@Suite("Setups list grouping (A10-94)")
@MainActor
struct SetupSectionsTests {

    /// Jakarta calendar, used both to build the dates and to group them,
    /// so the tests do not depend on the machine's time zone.
    private static let jakarta: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return calendar
    }()

    private let calendar = SetupSectionsTests.jakarta

    private func date(day: Int, month: Int = 11, year: Int = 2026, hour: Int = 10, minute: Int = 0) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return SetupSectionsTests.jakarta.date(from: parts)!
    }

    /// A setup built outside a store, with an optional first saved date (nil = draft).
    private func makeSetup(_ name: String, client: String = "", saved: Date?) -> Setup {
        let setup = Setup(setupName: name, client: client)
        setup.firstSavedDate = saved
        return setup
    }

    @Test("Case 1: newest month first, each setup under its month")
    func newestMonthFirst() {
        // Arrange
        let shoe = makeSetup("Shoe shoot", saved: date(day: 2))
        let bag = makeSetup("Bag shoot", saved: date(day: 15, month: 10))

        // Act
        let sections = SetupSections.recent(from: [bag, shoe], calendar: calendar)

        // Assert
        #expect(sections.map(\.title) == ["November 2026", "October 2026"])
        #expect(sections[safe: 0]?.setups.map(\.setupName) == ["Shoe shoot"])
        #expect(sections[safe: 1]?.setups.map(\.setupName) == ["Bag shoot"])
    }

    @Test("Case 2: inside a month, names A to Z")
    func namesAlphabeticalInsideMonth() {
        // Arrange
        let watch = makeSetup("Watch", saved: date(day: 5))
        let bag = makeSetup("Bag", saved: date(day: 2))

        // Act
        let sections = SetupSections.recent(from: [watch, bag], calendar: calendar)

        // Assert
        #expect(sections.map(\.title) == ["November 2026"])
        #expect(sections.first?.setups.map(\.setupName) == ["Bag", "Watch"])
    }

    @Test("Case 3: an early-morning save counts in the Jakarta month")
    func earlyMorningSaveUsesJakartaMonth() {
        // Arrange: 02:00 on 1 Nov in Jakarta is still 31 Oct in UTC, so a wrong time zone would say October.
        let late = makeSetup("Late shoot", saved: date(day: 1, month: 11, hour: 2))

        // Act
        let sections = SetupSections.recent(from: [late], calendar: calendar)

        // Assert
        #expect(sections.map(\.title) == ["November 2026"])
        #expect(sections[safe: 0]?.setups.map(\.setupName) == ["Late shoot"])
    }

    @Test("Case 4: clients sorted A to Z, ignoring case")
    func clientsSortedIgnoringCase() {
        // Arrange
        let bose = makeSetup("Speaker", client: "Bose", saved: date(day: 2))
        let apple = makeSetup("Phone", client: "apple", saved: date(day: 2))

        // Act
        let groups = SetupSections.byClient(from: [bose, apple], calendar: calendar)

        // Assert
        #expect(groups.map(\.title) == ["apple", "Bose"])
    }

    @Test("Case 5: client names that differ only by case or spaces share one heading")
    func sameClientSharesHeading() {
        // Arrange
        let ring = makeSetup("Ring", client: "Acme", saved: date(day: 2))
        let box = makeSetup("Box", client: "acme ", saved: date(day: 5))

        // Act
        let groups = SetupSections.byClient(from: [ring, box], calendar: calendar)

        // Assert
        #expect(groups.map(\.title) == ["acme"], "The newest setup (Box) decides the spelling, trimmed.")
        let names = groups.flatMap(\.sections).flatMap(\.setups).map(\.setupName)
        #expect(Set(names) == ["Ring", "Box"])
    }

    @Test("Case 6: empty or blank client goes to No Client, last")
    func noClientGroupIsLast() {
        // Arrange
        let apple = makeSetup("Lamp", client: "Apple", saved: date(day: 2))
        let empty = makeSetup("Empty client", client: "", saved: date(day: 2))
        let blank = makeSetup("Blank client", client: "   ", saved: date(day: 2))

        // Act
        let groups = SetupSections.byClient(from: [empty, apple, blank], calendar: calendar)

        // Assert
        #expect(groups.map(\.title) == ["Apple", "No Client"])
        let noClientNames = groups.last?.sections.flatMap(\.setups).map(\.setupName) ?? []
        #expect(Set(noClientNames) == ["Empty client", "Blank client"])
    }

    @Test("Case 7: inside a client, newest month first and names A to Z")
    func monthsInsideClient() {
        // Arrange
        let lamp = makeSetup("Lamp", client: "Apple", saved: date(day: 10, month: 10))
        let cup = makeSetup("Cup", client: "Apple", saved: date(day: 3))
        let bowl = makeSetup("Bowl", client: "Apple", saved: date(day: 20))

        // Act
        let groups = SetupSections.byClient(from: [lamp, cup, bowl], calendar: calendar)

        // Assert
        #expect(groups.map(\.title) == ["Apple"])
        let sections = groups[safe: 0]?.sections ?? []
        #expect(sections.map(\.title) == ["November 2026", "October 2026"])
        #expect(sections[safe: 0]?.setups.map(\.setupName) == ["Bowl", "Cup"])
        #expect(sections[safe: 1]?.setups.map(\.setupName) == ["Lamp"])
    }

    @Test("Case 8: drafts sit on top of Recent in a Not saved section")
    func draftsOnTopOfRecent() {
        // Arrange
        let draft = makeSetup("New Setup", saved: nil)
        let shoe = makeSetup("Shoe shoot", saved: date(day: 2))

        // Act
        let sections = SetupSections.recent(from: [shoe, draft], calendar: calendar)

        // Assert
        #expect(sections.map(\.title) == ["Not saved", "November 2026"])
        #expect(sections[safe: 0]?.setups.map(\.setupName) == ["New Setup"])
    }

    @Test("Case 9: drafts sit on top of By Client, whatever their client")
    func draftsOnTopOfByClient() {
        // Arrange
        let draft = makeSetup("New Setup", client: "Apple", saved: nil)
        let shoe = makeSetup("Shoe shoot", client: "Apple", saved: date(day: 2))

        // Act
        let groups = SetupSections.byClient(from: [shoe, draft], calendar: calendar)

        // Assert
        #expect(groups.map(\.title) == ["Not saved", "Apple"])
        #expect(groups[safe: 0]?.sections.map(\.title) == [""], "Drafts have no month heading.")
        #expect(groups[safe: 0]?.sections.flatMap(\.setups).map(\.setupName) == ["New Setup"])
        #expect(groups[safe: 1]?.sections.flatMap(\.setups).map(\.setupName) == ["Shoe shoot"])
    }

    @Test("Case 10: no setups gives no sections, and the empty state")
    func noSetups() {
        // Arrange
        let viewModel = SetupsViewModel(storageController: StorageController(inMemory: true))

        // Act
        let recent = SetupSections.recent(from: [], calendar: calendar)
        let byClient = SetupSections.byClient(from: [], calendar: calendar)

        // Assert
        #expect(recent.isEmpty)
        #expect(byClient.isEmpty)
        #expect(viewModel.showsEmptyState)
        #expect(viewModel.recentSections.isEmpty)
        #expect(viewModel.clientGroups.isEmpty)
    }
}

private extension Array {
    /// Returns nil instead of crashing, so a wrong result fails one test and not the whole run.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
