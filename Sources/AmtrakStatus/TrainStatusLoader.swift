import AmtrakClient
import Foundation
import Logging

/// The outcome of loading one station's trains.
enum BoardUpdate: Equatable, Sendable {
  /// New rows. `stationName` is `nil` when Amtraker gave no usable name, and
  /// `unavailableTrains` lists train numbers that could not be read.
  case loaded(
    stationName: String?,
    rows: [TrainStatusRow],
    timeZone: TimeZone?,
    unavailableTrains: [String]
  )
  /// Amtraker does not know the station.
  case stationNotFound(code: String)
  /// Nothing could be loaded, and `message` says why.
  case failed(message: String)
}

/// Loads board data away from the render thread.
protocol TrainStatusLoading: Sendable {
  func update(forStation code: String) async -> BoardUpdate
}

/// Loads board data from Amtraker.
struct AmtrakerStatusLoader: TrainStatusLoading {
  private static let logger = Logger(label: "com.tonybark.AmtrakStatus")

  private let client = AmtrakClient()

  func update(forStation code: String) async -> BoardUpdate {
    Self.logger.info("Starting train status refresh for station \(code)")
    do {
      let lookup = try await client.trainStationLookup(stationCode: code)
      let staleData = try await client.fetchStaleStatus()

      var trains: [Train] = []
      var unavailableTrains: [String] = []
      var lastError: (any Error)?
      for number in lookup.trainNumbers {
        do {
          trains += try await client.fetchAllTrainStatus(num: number)
        } catch {
          Self.logger.error("Train \(number) is unavailable: \(error.localizedDescription)")
          unavailableTrains.append(number)
          lastError = error
        }
      }

      if trains.isEmpty, let lastError {
        return .failed(message: Self.message(for: lastError))
      }

      let rows = TrainStatusRows.make(
        from: trains,
        atStation: code,
        staleTimes: TrainStatusRows.staleTimes(from: staleData),
        timeZone: lookup.timeZone,
        now: Date()
      )
      Self.logger.info("Train status refresh completed with \(rows.count) active rows")
      return .loaded(
        stationName: StationHeading.make(name: lookup.name, state: lookup.state),
        rows: rows,
        timeZone: lookup.timeZone,
        unavailableTrains: unavailableTrains.sorted()
      )
    } catch AmtrakError.stationNotFound(let code) {
      Self.logger.error("Station \(code) was not found")
      return .stationNotFound(code: code)
    } catch {
      Self.logger.error("Train status refresh failed: \(error.localizedDescription)")
      return .failed(message: Self.message(for: error))
    }
  }

  private static func message(for error: any Error) -> String {
    switch error {
    case AmtrakError.httpStatus(let code):
      "AMTRAKER RETURNED HTTP \(code)"
    case AmtrakError.invalidURL(let url):
      "INVALID API URL: \(url)"
    case AmtrakError.invalidResponse:
      "AMTRAKER RETURNED AN INVALID RESPONSE"
    case is DecodingError:
      "AMTRAKER RETURNED UNREADABLE DATA"
    default:
      "UPDATE FAILED: \(error.localizedDescription)".uppercased()
    }
  }
}

/// Turns Amtraker's station details into the name at the top of the board.
enum StationHeading {
  /// Returns text such as "NEW YORK PENN, NY", or `nil` when `name` is blank. The state is left
  /// off when Amtraker has none, or when the name already ends with it.
  static func make(name: String, state: String?) -> String? {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !name.isEmpty else { return nil }

    let state = (state ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !state.isEmpty, !name.hasSuffix(", \(state)") else { return name }
    return "\(name), \(state)"
  }
}

/// Turns Amtraker's trains into board rows.
enum TrainStatusRows {
  private static let staleDataThreshold: TimeInterval = 60 * 60 * 48

  /// Returns how many seconds it has been since Amtraker heard about each train, by train ID.
  static func staleTimes(from data: StaleData) -> [String: TimeInterval] {
    Dictionary(
      data.lastUpdatedArr.map { ($0.trainID, $0.timeSince / 1000) },
      uniquingKeysWith: { first, _ in first }
    )
  }

  /// Returns a row for each train stopping at `code`, soonest first. Trains that departed on
  /// an earlier day, or that Amtraker has not heard from recently, are left out.
  ///
  /// Trains with the same time sort by ID, so rows keep their places between refreshes.
  static func make(
    from trains: [Train],
    atStation code: String,
    staleTimes: [String: TimeInterval],
    timeZone: TimeZone?,
    now: Date
  ) -> [TrainStatusRow] {
    let dates = BoardDateFormatting()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone ?? .current

    let rows = trains.compactMap { train -> TrainStatusRow? in
      guard let leg = train.stations?.first(where: { $0.code == code }),
        !hasDeparted(leg, before: calendar.startOfDay(for: now), dates: dates),
        staleTimes[train.trainID].map({ $0 <= staleDataThreshold }) ?? true
      else {
        return nil
      }

      return TrainStatusRow(
        trainID: train.trainID,
        scheduledArrival: dates.parsedDate(from: leg.schArr),
        estimatedArrival: dates.parsedDate(from: leg.arr),
        trainNum: train.trainNum,
        runDay: runDay(fromTrainID: train.trainID),
        service: train.routeName,
        destination: train.destName,
        punctuality: dates.punctuality(actual: leg.arr, scheduled: leg.schArr)
      )
    }

    return rows.sorted {
      let first = $0.scheduledArrival ?? .distantFuture
      let second = $1.scheduledArrival ?? .distantFuture
      return first == second ? $0.trainID < $1.trainID : first < second
    }
  }

  /// Returns the day of the month a run started from Amtraker's train ID, such as 3 for `67-3`,
  /// or `nil` when the ID has no day.
  static func runDay(fromTrainID id: String) -> Int? {
    guard let dash = id.lastIndex(of: "-") else { return nil }
    return Int(id[id.index(after: dash)...]).flatMap { (1...31).contains($0) ? $0 : nil }
  }

  private static func hasDeparted(
    _ leg: Station,
    before startOfToday: Date,
    dates: BoardDateFormatting
  ) -> Bool {
    guard leg.status == .departed,
      let departure = dates.parsedDate(from: leg.dep) ?? dates.parsedDate(from: leg.schDep)
    else {
      return false
    }
    return departure < startOfToday
  }
}
