import Foundation

/// Decides which screen frames may be written. Pure, so the ordering rules are unit-tested.
///
/// Before `arm`, frames are only held (the newest one). `arm(at:)` fixes the earliest allowed time stamp
/// to the end of the countdown, so a stale frame captured earlier can never become the time origin, and
/// every accepted frame has a strictly later time stamp than the one before.
struct FrameGate<Payload> {
    private(set) var isArmed: Bool
    private(set) var held: Payload?
    private var minimum = -Double.infinity
    private var last = -Double.infinity

    init(armed: Bool) { isArmed = armed }

    /// Keeps the newest frame seen while not armed.
    mutating func hold(_ payload: Payload) { held = payload }

    /// Opens the gate at `now` (host seconds) and returns the held frame, if any, to be written at `now`.
    mutating func arm(at now: Double) -> Payload? {
        isArmed = true
        minimum = now
        defer { held = nil }
        return held
    }

    /// True if a frame with this time stamp may be written next.
    mutating func accept(pts: Double) -> Bool {
        guard isArmed, pts >= minimum, pts > last else { return false }
        last = pts
        return true
    }
}
