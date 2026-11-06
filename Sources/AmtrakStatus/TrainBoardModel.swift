import Foundation
import Logging

/// The board's state. The render loop owns it and calls `update(now:)` once per frame, which
/// starts refreshes on background tasks and applies whatever they have finished.
final class TrainBoardModel {
  private static let logger = Logger(label: "com.tonybark.AmtrakStatus")

  private struct Delivery: Sendable {
    let selection: Int
    let update: BoardUpdate
  }

  private(set) var stationCode: String
  private(set) var stationName: String
  private(set) var rows: [TrainStatusRow] = []
  private(set) var statusMessage = "CONNECTING TO AMTRAKER"
  private(set) var lastUpdatedAt: Date?
  private(set) var problem: String?

  private let loader: any TrainStatusLoading
  private let refreshInterval: TimeInterval
  /// How many hours ahead the board shows trains, or `nil` for no limit.
  private let lookAheadHours: Int?
  private let mailbox = Mailbox<Delivery>()
  private let dates = BoardDateFormatting()
  /// The station's time zone, once known.
  private(set) var timeZone: TimeZone?
  // Counts station changes, so a result for an earlier station can be recognized and dropped.
  private var selection = 0
  private var isRefreshing = false
  private var nextRefresh = Date.distantPast
  // Whether the next refresh may use cached data. Only the first one for a station does: timed
  // refreshes come an interval after the last, when the cache has nothing newer.
  private var mayReuseCache = true

  init(
    stationCode: String,
    stationName: String,
    refreshInterval: TimeInterval,
    lookAheadHours: Int? = nil,
    loader: any TrainStatusLoading
  ) {
    self.stationCode = stationCode
    self.stationName = stationName
    self.refreshInterval = refreshInterval
    self.lookAheadHours = lookAheadHours
    self.loader = loader
    timeZone = TimeZone(identifier: "America/New_York")
  }

  /// The current time at the station.
  func stationTime(now: Date) -> String {
    dates.time(of: now, in: timeZone)
  }

  /// The rows to show at `now`: those due within the look-ahead, soonest first.
  func shownRows(now: Date) -> [TrainStatusRow] {
    TrainStatusRows.due(rows, within: lookAheadHours, of: now)
  }

  /// What the board says when `shownRows(now:)` is empty. It names the look-ahead only when
  /// that is what emptied the board.
  var emptyMessage: String {
    guard let lookAheadHours, !rows.isEmpty else { return statusMessage }
    return lookAheadHours == 1
      ? "NO TRAINS IN THE NEXT HOUR" : "NO TRAINS IN THE NEXT \(lookAheadHours) HOURS"
  }

  /// One line on how fresh the rows are, including anything wrong with the latest refresh.
  var updateSummary: String {
    let updated = lastUpdatedAt.map { dates.time(of: $0, in: timeZone) }
    switch (updated, problem) {
    case (let updated?, let problem?):
      return "\(problem)  /  SHOWING DATA FROM \(updated)"
    case (let updated?, nil):
      return "UPDATED \(updated)"
    case (nil, let problem?):
      return problem
    case (nil, nil):
      return "WAITING FOR FIRST UPDATE"
    }
  }

  /// Applies finished refreshes and starts a new one when it is due.
  func update(now: Date) {
    for delivery in mailbox.collect() where delivery.selection == selection {
      isRefreshing = false
      apply(delivery.update)
    }

    guard now >= nextRefresh, !isRefreshing else { return }
    nextRefresh = now.addingTimeInterval(refreshInterval)
    startRefresh()
  }

  /// Changes the station and refreshes on the next `update(now:)`. Rows and results from the
  /// previous station are dropped. `name` shows until a refresh brings Amtraker's name.
  func selectStation(code: String, named name: String) {
    selection += 1
    stationCode = code
    stationName = name
    rows = []
    timeZone = nil
    lastUpdatedAt = nil
    problem = nil
    statusMessage = "FETCHING TRAIN STATUS"
    isRefreshing = false
    nextRefresh = .distantPast
    mayReuseCache = true
  }

  private func startRefresh() {
    isRefreshing = true
    if lastUpdatedAt == nil, problem == nil {
      statusMessage = "FETCHING TRAIN STATUS"
    }
    let maxAge = mayReuseCache ? refreshInterval : nil
    mayReuseCache = false
    let (loader, mailbox, code, selection) = (loader, mailbox, stationCode, selection)
    Task.detached {
      let update = await loader.update(forStation: code, reusingCacheWithin: maxAge)
      mailbox.deliver(Delivery(selection: selection, update: update))
    }
  }

  private func apply(_ update: BoardUpdate) {
    switch update {
    case .loaded(
      let stationName, let rows, let timeZone, let problem, let fetchedAt, let reportedTrainIDs):
      if let reportedTrainIDs {
        logVanished(TrainStatusRows.vanished(from: self.rows, reported: reportedTrainIDs))
      }
      self.stationName = stationName ?? self.stationName
      self.rows = rows
      self.timeZone = timeZone ?? self.timeZone
      lastUpdatedAt = fetchedAt
      // Cached data is older than this refresh, so its next refresh is due sooner.
      nextRefresh = min(nextRefresh, fetchedAt.addingTimeInterval(refreshInterval))
      self.problem = problem
      statusMessage = problem ?? "NO ACTIVE TRAINS REPORTED"
    case .stationNotFound(let code):
      rows = []
      lastUpdatedAt = nil
      problem = "STATION \(code) NOT FOUND"
      statusMessage = "STATION \(code) NOT FOUND"
    case .failed(let message):
      problem = message
      statusMessage = message
    }
  }

  /// Notes trains that left the board because Amtraker stopped reporting them, not because
  /// they departed, so how often that happens can be seen with `--verbose`.
  private func logVanished(_ rows: [TrainStatusRow]) {
    for row in rows {
      let due = row.scheduledArrival.map { dates.time(of: $0, in: timeZone) } ?? "no time"
      Self.logger.info(
        """
        Train \(row.trainNum) (\(row.trainID)), due \(due) at \(stationCode), is no longer \
        reported by Amtraker and never departed
        """
      )
    }
  }
}
