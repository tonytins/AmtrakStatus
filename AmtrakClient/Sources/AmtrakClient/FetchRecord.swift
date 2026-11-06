import Foundation

/// Records what an `AmtrakClient` returned: when each response was fetched, including responses
/// taken from its cache, and the first failure a cached response stood in for. A caller can then
/// say how old a set of requests' data is, and why.
///
/// It is safe to use from any thread.
public final class FetchRecord: @unchecked Sendable {
  // Guards everything below.
  private let lock = NSLock()
  private var dates: [Date] = []
  private var failure: (any Error)?

  public init() {}

  /// When the oldest response was fetched, or `nil` before any response.
  public var oldest: Date? {
    lock.lock()
    defer { lock.unlock() }
    return dates.min()
  }

  /// The first failed request that a cached response stood in for, or `nil` when every
  /// response is as fresh as its request asked for.
  public var fallbackFailure: (any Error)? {
    lock.lock()
    defer { lock.unlock() }
    return failure
  }

  func noteResponse(fetchedAt date: Date) {
    lock.lock()
    defer { lock.unlock() }
    dates.append(date)
  }

  func noteFallback(after error: any Error) {
    lock.lock()
    defer { lock.unlock() }
    if failure == nil { failure = error }
  }
}
