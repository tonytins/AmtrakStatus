import Foundation

/// Collects when each response an `AmtrakClient` returned was fetched, including responses
/// reused from its cache, so a caller can say how old a set of requests' data is.
///
/// It is safe to use from any thread.
public final class FetchDates: @unchecked Sendable {
  // Guards `dates`.
  private let lock = NSLock()
  private var dates: [Date] = []

  public init() {}

  /// When the oldest response was fetched, or `nil` before any response.
  public var oldest: Date? {
    lock.lock()
    defer { lock.unlock() }
    return dates.min()
  }

  func note(_ date: Date) {
    lock.lock()
    defer { lock.unlock() }
    dates.append(date)
  }
}
