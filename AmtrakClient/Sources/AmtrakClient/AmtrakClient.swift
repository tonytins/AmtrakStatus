import Foundation
import Logging
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Errors returned while requesting or decoding Amtraker data.
public enum AmtrakError: Error {
  case invalidURL(String)
  case invalidResponse
  case httpStatus(Int)
  case stationNotFound(String)
}

/// A station's name and location, with the train numbers and time zone associated with it.
public struct TrainStationLookUp: Sendable {
  /// The name as Amtraker reports it, such as "New York Penn".
  public var name: String
  /// The state or province abbreviation. Amtraker reports none for some stations.
  public var state: String?
  public var trainNumbers: [String]
  public var timeZone: TimeZone?

  public init(name: String, state: String?, trainNumbers: [String], timeZone: TimeZone?) {
    self.name = name
    self.state = state
    self.trainNumbers = trainNumbers
    self.timeZone = timeZone
  }
}

/// Where an `AmtrakClient` may take its responses from.
public enum Freshness: Sendable, Equatable {
  /// Always ask Amtraker.
  case fetch
  /// Use a cached response fetched within `maxAge` seconds, and ask Amtraker otherwise.
  case reuse(maxAge: TimeInterval)
}

/// Fetches train and station data from the Amtraker API.
///
/// With a cache, every response that decodes is saved, so a later client can reuse it, and a
/// request that fails returns the saved response instead, however old.
public struct AmtrakClient: Sendable {
  private static let logger = Logger(label: "com.tonybark.AmtrakClient")
  private static let stationBaseURL = "https://api.amtraker.com/v3/stations"
  private static let trainsBaseURL = "https://api.amtraker.com/v3/trains"
  private static let staleBaseURL = "https://api.amtraker.com/v3/stale"

  private let cache: ResponseCache?
  private let freshness: Freshness
  private let record: FetchRecord?

  /// Creates a client. `cache` keeps responses between requests and launches, `freshness` says
  /// whether a cached response may be used instead of asking Amtraker, and `record` collects
  /// when each returned response was fetched and which failures cached responses stood in for.
  public init(
    cache: ResponseCache? = nil,
    freshness: Freshness = .fetch,
    record: FetchRecord? = nil
  ) {
    self.cache = cache
    self.freshness = freshness
    self.record = record
  }

  public func fetchTrain(number trainid: String) async throws -> TrainResponse {
    try await get("\(Self.trainsBaseURL)/\(trainid)")
  }

  public func fetchAllTrains() async throws -> TrainResponse {
    try await get(Self.trainsBaseURL)
  }

  public func fetchStaleStatus() async throws -> StaleData {
    try await get(Self.staleBaseURL)
  }

  public func fetchAllTrainStatus(num trainNum: String) async throws -> [Train] {
    let response = try await fetchTrain(number: trainNum)
    return response.values.flatMap(\.self)
  }

  public func fetchStation(code stationid: String) async throws -> StationResponse {
    try await get("\(Self.stationBaseURL)/\(stationid)")
  }

  public func fetchAllStations() async throws -> StationResponse {
    try await get(Self.stationBaseURL)
  }

  public func trainNumber(fromTrainId trainId: String) -> String {
    trainId
      .split(separator: "-")
      .first
      .map(String.init) ?? trainId
  }

  public func trainStationLookup(stationCode code: String) async throws -> TrainStationLookUp {
    let response = try await fetchStation(code: code)

    guard let meta = response[code] else {
      throw AmtrakError.stationNotFound(code)
    }

    let trainNumbers = Array(Set(meta.trains.map(trainNumber(fromTrainId:))))
    let timeZone = meta.tz.flatMap(TimeZone.init(identifier:))
    return TrainStationLookUp(
      name: meta.name,
      state: meta.state,
      trainNumbers: trainNumbers,
      timeZone: timeZone
    )
  }

  private func get<T: Decodable & Sendable>(_ urlString: String) async throws -> T {
    guard let url = URL(string: urlString) else {
      throw AmtrakError.invalidURL(urlString)
    }

    if let cached: T = reusableResponse(for: url) {
      return cached
    }

    Self.logger.debug("Fetching \(urlString)")

    do {
      let (data, response) = try await URLSession.shared.data(from: url)
      guard let http = response as? HTTPURLResponse else {
        throw AmtrakError.invalidResponse
      }

      guard (200..<300).contains(http.statusCode) else {
        throw AmtrakError.httpStatus(http.statusCode)
      }

      let decoded = try JSONDecoder().decode(T.self, from: data)
      Self.logger.info(
        "Fetched \(urlString): HTTP \(http.statusCode), \(data.count) bytes"
      )
      record?.noteResponse(fetchedAt: Date())
      save(data, for: url)
      return decoded
    } catch {
      if let fallback: T = fallbackResponse(for: url, after: error) {
        return fallback
      }
      Self.logger.error(
        "Fetch failed for \(urlString): \(error.localizedDescription)"
      )
      throw error
    }
  }

  /// Returns the cached response for `url` when `freshness` allows it and it still decodes.
  private func reusableResponse<T: Decodable>(for url: URL) -> T? {
    guard case .reuse(let maxAge) = freshness, let cache else { return nil }
    do {
      guard let entry = try cache.entry(for: url),
        Date().timeIntervalSince(entry.fetchedAt) <= maxAge
      else {
        return nil
      }
      let decoded = try JSONDecoder().decode(T.self, from: entry.data)
      Self.logger.info("Reused \(url.absoluteString) from the cache, fetched \(entry.fetchedAt)")
      record?.noteResponse(fetchedAt: entry.fetchedAt)
      return decoded
    } catch {
      Self.logger.warning(
        "Cached \(url.absoluteString) is unusable, fetching it: \(error.localizedDescription)"
      )
      return nil
    }
  }

  /// Returns the cached response for `url`, however old, to stand in for a failed request, or
  /// `nil` when there is none that decodes.
  private func fallbackResponse<T: Decodable>(for url: URL, after error: any Error) -> T? {
    guard let cache else { return nil }
    do {
      guard let entry = try cache.entry(for: url) else { return nil }
      let decoded = try JSONDecoder().decode(T.self, from: entry.data)
      Self.logger.warning(
        """
        Fetch failed for \(url.absoluteString): \(error.localizedDescription). \
        Using the cached copy from \(entry.fetchedAt) instead.
        """
      )
      record?.noteResponse(fetchedAt: entry.fetchedAt)
      record?.noteFallback(after: error)
      return decoded
    } catch let cacheError {
      Self.logger.warning(
        "Cached \(url.absoluteString) can't stand in: \(cacheError.localizedDescription)"
      )
      return nil
    }
  }

  /// Saves a response that decoded. A failure only costs the next launch a request.
  private func save(_ data: Data, for url: URL) {
    do {
      try cache?.save(data, for: url)
    } catch {
      Self.logger.warning(
        "Could not cache \(url.absoluteString): \(error.localizedDescription)"
      )
    }
  }
}
