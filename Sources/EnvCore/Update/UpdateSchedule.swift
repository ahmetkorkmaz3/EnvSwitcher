import Foundation

/// The app checks for a new release at most once a day (spec 2026-10-08, section 7.1).
public enum UpdateSchedule {
    public static let interval: TimeInterval = 24 * 60 * 60

    /// A last check in the future means the clock moved back. The check then runs, so it never stops.
    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return lastCheck > now || now.timeIntervalSince(lastCheck) >= interval
    }
}
