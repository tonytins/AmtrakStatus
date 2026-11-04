import Foundation

/// Carries values from background tasks to the render loop, which collects them each frame.
///
/// The render loop owns the main thread and never suspends, so it cannot await these values.
final class Mailbox<Value: Sendable>: @unchecked Sendable {
  // Guards `values`.
  private let lock = NSLock()
  private var values: [Value] = []

  func deliver(_ value: Value) {
    lock.lock()
    defer { lock.unlock() }
    values.append(value)
  }

  /// Removes and returns everything delivered so far, oldest first.
  func collect() -> [Value] {
    lock.lock()
    defer { lock.unlock() }
    defer { values.removeAll() }
    return values
  }
}
