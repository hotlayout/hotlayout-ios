import Foundation

/// A value that several threads read and change, always under one lock. The only place the package
/// vouches for thread safety by hand; a cache that must be shared goes into one of these instead of
/// a `static var` next to a separate lock.
final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    /// Runs `body` with exclusive access to the value. `body` must not call back into the same lock.
    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
