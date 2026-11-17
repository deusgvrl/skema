import Foundation

/// The 30-day rule for Recently Deleted (A10-95).
enum RecentlyDeleted {
    static let keepDays = 30

    /// Whole calendar days left before the setup is removed; negative once it is past its last day.
    static func daysLeft(deletedOn deletedDate: Date, now: Date, calendar: Calendar) -> Int {
        let deletedDay = calendar.startOfDay(for: deletedDate)
        let today = calendar.startOfDay(for: now)
        let daysPassed = calendar.dateComponents([.day], from: deletedDay, to: today).day ?? 0
        return keepDays - daysPassed
    }

    /// "1 day left", otherwise "N days left" (0 gives "0 days left").
    static func daysLeftText(_ days: Int) -> String {
        days == 1 ? "1 day left" : "\(days) days left"
    }

    /// True once the setup is past its last day. Goes through `daysLeft` so there is one rule only.
    static func isExpired(deletedOn deletedDate: Date, now: Date, calendar: Calendar) -> Bool {
        daysLeft(deletedOn: deletedDate, now: now, calendar: calendar) < 0
    }
}
