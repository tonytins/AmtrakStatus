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

/// Fetches train and station data from the Amtraker API.
public struct AmtrakClient: Sendable {
  private static let logger = Logger(label: "com.tonybark.AmtrakClient")
  private static let stationBaseURL = "https://api.amtraker.com/v3/stations"
  private static let trainsBaseURL = "https://api.amtraker.com/v3/trains"
  private static let staleBaseURL = "https://api.amtraker.com/v3/stale"

  public init() {}

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
      return decoded
    } catch {
      Self.logger.error(
        "Fetch failed for \(urlString): \(error.localizedDescription)"
      )
      throw error
    }
  }
}
