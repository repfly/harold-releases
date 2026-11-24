import Foundation

/// The wait before each reconnect: 1, 2 and 5 seconds, then 10 seconds.
struct ReconnectSchedule: Sendable {
    let steps: [TimeInterval] = [1, 2, 5]
    let steady: TimeInterval = 10

    func delay(afterFailures count: Int) -> TimeInterval {
        count < steps.count ? steps[count] : steady
    }
}
