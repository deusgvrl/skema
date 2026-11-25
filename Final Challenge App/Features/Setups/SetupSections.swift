import Foundation

/// One heading in the setups list and the setups under it.
struct SetupSection: Identifiable {
    var id: String { title }
    let title: String
    let setups: [Setup]
}

/// A client heading in the By Client view, with its month sections inside.
struct ClientGroup: Identifiable {
    var id: String { title }
    let title: String
    let sections: [SetupSection]
}

/// Builds the setups list headings (A10-94). Pure: same setups in, same sections out.
enum SetupSections {
    static let notSavedTitle = "Not Saved"
    static let noClientTitle = "No Client"

    static func recent(from setups: [Setup], calendar: Calendar = .current) -> [SetupSection] {
        let (drafts, saved) = split(setups)
        var sections = monthSections(from: saved, calendar: calendar)
        if !drafts.isEmpty {
            sections.insert(SetupSection(title: notSavedTitle, setups: sortedByName(drafts)), at: 0)
        }
        return sections
    }

    static func byClient(from setups: [Setup], calendar: Calendar = .current) -> [ClientGroup] {
        let (drafts, saved) = split(setups)
        let byKey = Dictionary(grouping: saved) { clientKey(for: $0.client) }

        // An empty key means "no client". It goes last, so the real clients stay together at the top.
        let keys = byKey.keys.sorted { lhs, rhs in
            if lhs.isEmpty != rhs.isEmpty { return rhs.isEmpty }
            return lhs < rhs
        }
        var groups = keys.map { key in
            let members = byKey[key] ?? []
            return ClientGroup(
                title: key.isEmpty ? noClientTitle : heading(for: members),
                sections: monthSections(from: members, calendar: calendar)
            )
        }
        if !drafts.isEmpty {
            // Drafts have no month yet, so they get one section with no month heading.
            let draftSection = SetupSection(title: "", setups: sortedByName(drafts))
            groups.insert(ClientGroup(title: notSavedTitle, sections: [draftSection]), at: 0)
        }
        return groups
    }

    /// The key that decides which setups share a client heading.
    static func clientKey(for client: String) -> String {
        return client.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The clients of the saved setups, A to Z, each once, spelled like its By Client heading.
    static func clientNames(from setups: [Setup]) -> [String] {
        Dictionary(grouping: split(setups).saved) { clientKey(for: $0.client) }
            .filter { !$0.key.isEmpty }
            .sorted { $0.key < $1.key }
            .map { heading(for: $0.value) }
    }

    // MARK: - Helpers

    private static func split(_ setups: [Setup]) -> (drafts: [Setup], saved: [Setup]) {
        (setups.filter { $0.firstSavedDate == nil }, setups.filter { $0.firstSavedDate != nil })
    }

    private static func sortedByName(_ setups: [Setup]) -> [Setup] {
        setups.sorted { $0.setupName.caseInsensitiveCompare($1.setupName) == .orderedAscending }
    }

    /// Month sections, newest first, names A to Z inside each. Expects saved setups only.
    private static func monthSections(from saved: [Setup], calendar: Calendar) -> [SetupSection] {
        let byMonth = Dictionary(grouping: saved) { setup -> Date in
            let date = setup.firstSavedDate ?? .distantPast
            // The month is decided in the calendar's time zone, so a late-night save counts in local time.
            return calendar.dateInterval(of: .month, for: date)?.start ?? date
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        // A fixed locale, so the title looks the same on every phone.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "LLLL yyyy"

        return byMonth.keys.sorted(by: >).map { monthStart in
            SetupSection(title: formatter.string(from: monthStart), setups: sortedByName(byMonth[monthStart] ?? []))
        }
    }

    /// The client spelling of the newest saved setup, without leading or trailing spaces.
    private static func heading(for members: [Setup]) -> String {
        let newest = members.max { ($0.firstSavedDate ?? .distantPast) < ($1.firstSavedDate ?? .distantPast) }
        return (newest?.client ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
