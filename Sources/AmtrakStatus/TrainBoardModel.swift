import Foundation

/// The board's state. The render loop owns it and calls `update(now:)` once per frame, which
/// starts refreshes on background tasks and applies whatever they have finished.
final class TrainBoardModel {
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
  private let mailbox = Mailbox<Delivery>()
  private let dates = BoardDateFormatting()
  /// The station's time zone, once known.
  private(set) var timeZone: TimeZone?
  // Counts station changes, so a result for an earlier station can be recognized and dropped.
  private var selection = 0
  private var isRefreshing = false
  private var nextRefresh = Date.distantPast

  init(
    stationCode: String,
    stationName: String,
    refreshInterval: TimeInterval,
    loader: any TrainStatusLoading
  ) {
    self.stationCode = stationCode
    self.stationName = stationName
    self.refreshInterval = refreshInterval
    self.loader = loader
    timeZone = TimeZone(identifier: "America/New_York")
  }

  /// The current time at the station.
  func stationTime(now: Date) -> String {
    dates.time(of: now, in: timeZone)
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
      apply(delivery.update, now: now)
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
  }

  private func startRefresh() {
    isRefreshing = true
    if lastUpdatedAt == nil, problem == nil {
      statusMessage = "FETCHING TRAIN STATUS"
    }
    let (loader, mailbox, code, selection) = (loader, mailbox, stationCode, selection)
    Task.detached {
      let update = await loader.update(forStation: code)
      mailbox.deliver(Delivery(selection: selection, update: update))
    }
  }

  private func apply(_ update: BoardUpdate, now: Date) {
    switch update {
    case .loaded(let stationName, let rows, let timeZone, let unavailableTrains):
      self.stationName = stationName ?? self.stationName
      self.rows = rows
      self.timeZone = timeZone ?? self.timeZone
      lastUpdatedAt = now
      problem = Self.summary(ofUnavailable: unavailableTrains)
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

  private static func summary(ofUnavailable trains: [String]) -> String? {
    switch trains.count {
    case 0: nil
    case 1: "TRAIN \(trains[0]) UNAVAILABLE"
    default: "\(trains.count) TRAINS UNAVAILABLE"
    }
  }
}
