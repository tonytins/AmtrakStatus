import Foundation
import Hudini
import Testing

@testable import AmtrakClient
@testable import AmtrakStatus

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// MARK: - Helpers

private func stationJSON(code: String = "ASD", arr: String, dep: String, status: String) -> String {
  """
  {"name":"Ashland","code":"\(code)","tz":"America/New_York","bus":false,
   "schArr":"2026-11-04T09:07:00-05:00","schDep":"2026-11-04T09:08:00-05:00",
   "arr":\(arr),"dep":\(dep),"arrCmnt":"","depCmnt":"","status":"\(status)",
   "stopIconColor":"#2a893d","platform":""}
  """
}

private func train(
  id: String = "67-3",
  number: String = "67",
  arr: String = "null",
  dep: String = "null",
  status: String = "Enroute"
) throws -> Train {
  let json = """
    {"routeName":"Northeast Regional","trainNum":"\(number)","trainID":"\(id)",
     "origName":"Boston South","destName":"Newport News",
     "stations":[\(stationJSON(arr: arr, dep: dep, status: status))]}
    """
  return try JSONDecoder().decode(Train.self, from: Data(json.utf8))
}

private let newYork = TimeZone(identifier: "America/New_York")
private let beforeTheTrain = ISO8601DateFormatter().date(from: "2026-11-04T06:00:00-05:00")!
private let chicagoZone = TimeZone(identifier: "America/Chicago")

private func date(_ iso: String) -> Date {
  ISO8601DateFormatter().date(from: iso)!
}

private func rowText(in zone: TimeZone? = newYork, now: Date = beforeTheTrain) -> BoardRowText {
  BoardRowText(timeZone: zone, now: now, dates: BoardDateFormatting())
}

private func row(arriving iso: String, estimate: String? = nil) -> TrainStatusRow {
  TrainStatusRow(
    trainID: "67-3", scheduledArrival: date(iso), estimatedArrival: estimate.map(date),
    trainNum: "67", service: "Northeast Regional", destination: "Newport News",
    punctuality: .unknown)
}

private func rows(
  _ trains: [Train],
  staleTimes: [String: TimeInterval] = [:]
) -> [TrainStatusRow] {
  TrainStatusRows.make(from: trains, atStation: "ASD", staleTimes: staleTimes)
}

private struct StubLoader: TrainStatusLoading {
  let updates: [String: BoardUpdate]

  func update(forStation code: String, reusingCacheWithin maxAge: TimeInterval?) async
    -> BoardUpdate
  {
    updates[code] ?? .failed(message: "NO STUB")
  }
}

/// Holds a station's result back until the test releases it.
private actor GatedLoader: TrainStatusLoading {
  private var waiting: [CheckedContinuation<BoardUpdate, Never>] = []

  private(set) var maxAges: [TimeInterval?] = []

  func update(forStation code: String, reusingCacheWithin maxAge: TimeInterval?) async
    -> BoardUpdate
  {
    maxAges.append(maxAge)
    return await withCheckedContinuation { waiting.append($0) }
  }

  var waitingCount: Int { waiting.count }

  func releaseFirst(with update: BoardUpdate) {
    waiting.removeFirst().resume(returning: update)
  }
}

private func model(
  _ loader: any TrainStatusLoading,
  lookAheadHours: Int? = nil
) -> TrainBoardModel {
  TrainBoardModel(
    stationCode: "ASD",
    stationName: "ASHLAND, VA",
    refreshInterval: 600,
    lookAheadHours: lookAheadHours,
    loader: loader
  )
}

/// Runs the model's frame update until `condition` holds, as the render loop would.
private func pump(
  _ model: TrainBoardModel,
  now: Date = beforeTheTrain,
  until condition: () -> Bool
) async throws {
  for _ in 0..<500 {
    model.update(now: now)
    if condition() { return }
    try await Task.sleep(for: .milliseconds(5))
  }
  Issue.record("The model did not reach the expected state.")
}

private let sampleRow = TrainStatusRow(
  trainID: "67-3",
  scheduledArrival: nil,
  trainNum: "67",
  runDay: 3,
  service: "Northeast Regional",
  destination: "Newport News",
  punctuality: .unknown
)

// MARK: - API data

@Test("Stops with null arrival and departure times still decode")
func decodesNullTimes() throws {
  let decoded = try train(arr: "null", dep: "null")
  #expect(decoded.stations?.first?.arr == nil)
  #expect(decoded.stations?.first?.dep == nil)
}

@Test("A train with no arrival estimate has unknown punctuality")
func nullArrivalIsUnknown() throws {
  let row = try #require(rows([train(arr: "null")]).first)
  #expect(row.punctuality == .unknown)
  #expect(row.earlyDelay.isEmpty)
  #expect(row.lateDelay.isEmpty)
}

@Test(
  "Punctuality comes from the arrival estimate",
  arguments: [
    ("2026-11-04T09:07:00-05:00", LateTrain.onTime),
    ("2026-11-04T09:00:00-05:00", LateTrain.early(minutes: 7)),
    ("2026-11-04T09:27:00-05:00", LateTrain.late(minutes: 20)),
  ])
func punctuality(arrival: String, expected: LateTrain) throws {
  let row = try #require(rows([train(arr: "\"\(arrival)\"")]).first)
  #expect(row.punctuality == expected)
}

// MARK: - Response cache

/// Runs `body` with a cache in a new temporary folder, and deletes the folder afterward.
private func withCache(_ body: (ResponseCache) throws -> Void) throws {
  let folder = FileManager.default.temporaryDirectory
    .appendingPathComponent("AmtrakStatusTests-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  try body(ResponseCache(directory: folder))
}

private let trainURL = URL(string: "https://api.amtraker.com/v3/trains/67")!

@Test("A saved response comes back with the time it was fetched")
func cacheRoundTrip() throws {
  try withCache { cache in
    let before = Date().addingTimeInterval(-2)
    try cache.save(Data("{\"67\":[]}".utf8), for: trainURL)
    let entry = try #require(try cache.entry(for: trainURL))
    #expect(entry.data == Data("{\"67\":[]}".utf8))
    #expect(entry.fetchedAt >= before && entry.fetchedAt <= Date().addingTimeInterval(2))
  }
}

@Test("A URL with nothing saved has no entry, even before the folder exists")
func cacheMiss() throws {
  try withCache { cache in
    #expect(try cache.entry(for: trainURL) == nil)
    try cache.save(Data("[]".utf8), for: trainURL)
    #expect(try cache.entry(for: URL(string: "https://api.amtraker.com/v3/trains/6")!) == nil)
  }
}

@Test("A file name keeps the URL readable and safe for every platform")
func cacheFileName() {
  let cache = ResponseCache(directory: URL(fileURLWithPath: "/cache"))
  #expect(cache.file(for: trainURL).lastPathComponent == "api.amtraker.com%2Fv3%2Ftrains%2F67.json")
}

@Test("Each URL gets its own file, directly in the cache folder")
func cacheFileNames() throws {
  try withCache { cache in
    let urls = [
      "https://api.amtraker.com/v3/trains/67",
      "https://api.amtraker.com/v3/trains/6",
      "https://api.amtraker.com/v3/trains_67",
      "https://api.amtraker.com/v3/stations/ASD",
      "https://api.amtraker.com/v3/stale",
    ].map { URL(string: $0)! }
    for (index, url) in urls.enumerated() {
      try cache.save(Data("\(index)".utf8), for: url)
    }
    for (index, url) in urls.enumerated() {
      #expect(try cache.entry(for: url)?.data == Data("\(index)".utf8))
    }
    let files = try FileManager.default.contentsOfDirectory(atPath: cache.directory.path)
    #expect(files.count == urls.count)
  }
}

@Test("Saving again replaces the response and its date")
func cacheReplaces() throws {
  try withCache { cache in
    try cache.save(Data("old".utf8), for: trainURL)
    try age(trainURL, in: cache, by: 60 * 60)
    try cache.save(Data("new".utf8), for: trainURL)
    let entry = try #require(try cache.entry(for: trainURL))
    #expect(entry.data == Data("new".utf8))
    #expect(entry.fetchedAt > Date().addingTimeInterval(-60))
  }
}

@Test("Old responses are deleted, and newer ones and other files are kept")
func cachePrunes() throws {
  try withCache { cache in
    let stationURL = URL(string: "https://api.amtraker.com/v3/stations/ASD")!
    try cache.save(Data("old".utf8), for: trainURL)
    try cache.save(Data("new".utf8), for: stationURL)
    try age(trainURL, in: cache, by: 3 * 24 * 60 * 60)
    let other = cache.directory.appendingPathComponent("notes.txt")
    try Data("keep".utf8).write(to: other)
    try FileManager.default.setAttributes(
      [.modificationDate: Date.distantPast], ofItemAtPath: other.path)

    let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 60 * 60)
    let removed = try cache.removeEntries(fetchedBefore: twoDaysAgo)
    #expect(removed == 1)
    #expect(try cache.entry(for: trainURL) == nil)
    #expect(try cache.entry(for: stationURL)?.data == Data("new".utf8))
    #expect(FileManager.default.fileExists(atPath: other.path))
  }
}

@Test("Pruning a cache that was never written does nothing")
func cachePrunesNothing() throws {
  try withCache { cache in
    let removed = try cache.removeEntries(fetchedBefore: Date())
    #expect(removed == 0)
  }
}

@Test("The standard cache folder is named for the app, inside this user's cache folder")
func cacheStandardFolder() throws {
  let folder = try #require(ResponseCache.standardDirectory(named: "AmtrakStatus"))
  #expect(folder.lastPathComponent == "AmtrakStatus")
}

/// Moves the saved response for `url` back in time by `seconds`.
private func age(_ url: URL, in cache: ResponseCache, by seconds: TimeInterval) throws {
  let fetchedAt = try #require(try cache.entry(for: url)).fetchedAt
  try FileManager.default.setAttributes(
    [.modificationDate: fetchedAt.addingTimeInterval(-seconds)],
    ofItemAtPath: cache.file(for: url).path)
}

@Test("A client reuses a fresh cached response without asking Amtraker, and dates it")
func clientReusesCache() async throws {
  let folder = FileManager.default.temporaryDirectory
    .appendingPathComponent("AmtrakStatusTests-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  let cache = ResponseCache(directory: folder)
  let url = URL(string: "https://api.amtraker.com/v3/stations/ZZZ")!
  let station = """
    {"ZZZ":{"name":"Cached Station","code":"ZZZ","tz":"America/New_York","bus":false,
     "trains":["67-3"]}}
    """
  try cache.save(Data(station.utf8), for: url)
  let fetchedAt = try #require(try cache.entry(for: url)).fetchedAt

  // ZZZ is not a real station, so a request to Amtraker would fail rather than return this.
  let record = FetchRecord()
  let client = AmtrakClient(cache: cache, freshness: .reuse(maxAge: 600), record: record)
  let lookup = try await client.trainStationLookup(stationCode: "ZZZ")
  #expect(lookup.name == "Cached Station")
  #expect(lookup.trainNumbers == ["67"])
  #expect(record.oldest == fetchedAt)
  #expect(record.fallbackFailure == nil)
}

@Test("A failed request returns the cached response however old, and records the failure")
func clientFallsBackToCache() async throws {
  let folder = FileManager.default.temporaryDirectory
    .appendingPathComponent("AmtrakStatusTests-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  let cache = ResponseCache(directory: folder)
  let url = URL(string: "https://api.amtraker.com/v3/stations/ZZZ")!
  let station = """
    {"ZZZ":{"name":"Saved Station","code":"ZZZ","tz":"America/New_York","bus":false,
     "trains":["67-3"]}}
    """
  try cache.save(Data(station.utf8), for: url)
  let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
  try FileManager.default.setAttributes(
    [.modificationDate: weekAgo], ofItemAtPath: cache.file(for: url).path)

  // Asking Amtraker for ZZZ fails either way: it returns data that doesn't decode, or there is
  // no network. The week-old copy stands in.
  let record = FetchRecord()
  let client = AmtrakClient(cache: cache, freshness: .fetch, record: record)
  let lookup = try await client.trainStationLookup(stationCode: "ZZZ")
  #expect(lookup.name == "Saved Station")
  let oldest = try #require(record.oldest)
  #expect(abs(oldest.timeIntervalSince(weekAgo)) < 1)
  #expect(record.fallbackFailure != nil)
}

@Test("Without a cached copy, a failed request still fails")
func clientFailsWithoutCache() async throws {
  let folder = FileManager.default.temporaryDirectory
    .appendingPathComponent("AmtrakStatusTests-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  let client = AmtrakClient(cache: ResponseCache(directory: folder), freshness: .fetch)
  await #expect(throws: (any Error).self) {
    try await client.trainStationLookup(stationCode: "ZZZ")
  }
}

@Test("A board's problem puts old data before unreadable trains")
func loadedProblems() {
  let fresh = FetchRecord()
  #expect(AmtrakerStatusLoader.problem(unavailableTrains: [], record: fresh) == nil)
  #expect(
    AmtrakerStatusLoader.problem(unavailableTrains: ["1124"], record: fresh)
      == "TRAIN 1124 UNAVAILABLE")
  #expect(
    AmtrakerStatusLoader.problem(unavailableTrains: ["1124", "67"], record: fresh)
      == "2 TRAINS UNAVAILABLE")

  let offline = FetchRecord()
  offline.noteFallback(after: URLError(.notConnectedToInternet))
  #expect(
    AmtrakerStatusLoader.problem(unavailableTrains: ["1124"], record: offline)
      == "COULD NOT REACH AMTRAKER")
  let serverError = FetchRecord()
  serverError.noteFallback(after: AmtrakError.httpStatus(503))
  #expect(
    AmtrakerStatusLoader.problem(unavailableTrains: [], record: serverError)
      == "AMTRAKER RETURNED HTTP 503")
}

// MARK: - Rows

@Test("Rows use only the characters the board's font can draw")
func boardTimeIsASCII() throws {
  let row = try #require(rows([train()]).first)
  let time = rowText().value(of: .time, in: row)
  #expect(time == "09:07")
  #expect(time.utf8.count == time.count)

  let clock = BoardDateFormatting().time(of: beforeTheTrain, in: newYork)
  #expect(clock == "06:00")
}

@Test("Rows carry the schedule, the estimate, and the run day as data")
func rowData() throws {
  let row = try #require(rows([train(arr: "\"2026-11-04T09:27:00-05:00\"")]).first)
  #expect(row.scheduledArrival == ISO8601DateFormatter().date(from: "2026-11-04T09:07:00-05:00"))
  #expect(row.estimatedArrival == ISO8601DateFormatter().date(from: "2026-11-04T09:27:00-05:00"))
  #expect(row.runDay == 3)
}

@Test(
  "The run day comes from the end of the train ID",
  arguments: [
    ("67-3", 3), ("3-21", 21), ("1689-21", 21), ("v690-3", 3),
    ("67", nil), ("67-", nil), ("67-x", nil), ("67-0", nil), ("67-32", nil),
  ] as [(String, Int?)])
func runDays(id: String, day: Int?) {
  #expect(TrainStatusRows.runDay(fromTrainID: id) == day)
}

@Test("A row without a scheduled time shows dashes")
func missingScheduleShowsDashes() {
  let text = rowText()
  #expect(text.value(of: .time, in: sampleRow) == "--")
}

@Test("Times are written in the station's time zone")
func timesUseStationZone() throws {
  let row = try #require(rows([train()]).first)
  let chicago = rowText(in: chicagoZone)
  #expect(chicago.value(of: .time, in: row) == "08:07")
}

@Test(
  "Times not today at the station show their weekday after the time",
  arguments: [
    // The board's time is 06:00 on Wednesday, November 4.
    ("2026-11-04T09:07:00-05:00", "09:07"),
    ("2026-11-04T23:59:00-05:00", "23:59"),
    ("2026-11-05T09:07:00-05:00", "09:07 THU"),
    ("2026-11-03T23:50:00-05:00", "23:50 TUE"),
    ("2026-11-10T09:07:00-05:00", "09:07 TUE"),
  ])
func weekdayMarkers(arrival: String, expected: String) {
  #expect(rowText().value(of: .time, in: row(arriving: arrival)) == expected)
}

@Test("Today is the station's day, not this computer's")
func todayIsTheStationsDay() {
  // 00:30 Thursday in New York is still 23:30 Wednesday in Chicago.
  let now = date("2026-11-05T00:30:00-05:00")
  let arriving = row(arriving: "2026-11-04T23:50:00-06:00")
  #expect(rowText(in: chicagoZone, now: now).value(of: .time, in: arriving) == "23:50")
  #expect(rowText(in: newYork, now: now).value(of: .time, in: arriving) == "00:50")
  let late = row(arriving: "2026-11-04T22:50:00-05:00")
  #expect(rowText(in: newYork, now: now).value(of: .time, in: late) == "22:50 WED")
}

@Test("A marker appears at midnight without a refresh")
func markerFollowsTheClock() {
  let arriving = row(arriving: "2026-11-04T23:50:00-05:00")
  let beforeMidnight = rowText(now: date("2026-11-04T23:55:00-05:00"))
  let afterMidnight = rowText(now: date("2026-11-05T00:05:00-05:00"))
  #expect(beforeMidnight.value(of: .time, in: arriving) == "23:50")
  #expect(afterMidnight.value(of: .time, in: arriving) == "23:50 WED")
}

@Test("Trains that share a time keep their order between refreshes")
func rowOrderIsStable() throws {
  let first = try train(id: "1-1", number: "1")
  let second = try train(id: "2-1", number: "2")
  #expect(rows([first, second]).map(\.trainID) == ["1-1", "2-1"])
  #expect(rows([second, first]).map(\.trainID) == ["1-1", "2-1"])
}

@Test(
  "A train leaves the board once it departs, and stays while arriving or at the platform",
  arguments: [("Enroute", true), ("Station", true), ("Departed", false)])
func departedTrainsLeave(status: String, isShown: Bool) throws {
  let arriving = try train(dep: "\"2026-11-04T09:08:00-05:00\"", status: status)
  #expect(rows([arriving]).isEmpty != isShown)
}

@Test("Silent trains are left out")
func staleTrainsAreLeftOut() throws {
  let silent = try train()
  #expect(rows([silent], staleTimes: ["67-3": 60 * 60 * 49]).isEmpty)
  #expect(rows([silent], staleTimes: ["67-3": 60]).count == 1)
}

@Test(
  "Only trains silent for more than 48 hours count as stale, from Amtraker's milliseconds",
  arguments: [
    // 180 seconds, the age Amtraker's whole feed reaches between its updates.
    (180_000.0, true),
    // 47 hours and 49 hours.
    (169_200_000.0, true),
    (176_400_000.0, false),
  ])
func staleTimesAreMilliseconds(timeSince: Double, isShown: Bool) throws {
  let json = """
    {"activeTrains":1,"avgLastUpdate":0,"medianLastUpdate":0,
     "lastUpdatedArr":[{"trainID":"67-3","timeSince":\(timeSince)}]}
    """
  let data = try JSONDecoder().decode(StaleData.self, from: Data(json.utf8))
  let arriving = try train()
  let shown = rows([arriving], staleTimes: TrainStatusRows.staleTimes(from: data))
  #expect(shown.isEmpty != isShown)
}

@Test(
  "The look-ahead uses the estimate, and falls back to the schedule",
  arguments: [
    // The board's time is 06:00 on November 4, so a 6-hour look-ahead ends at 12:00.
    ("2026-11-04T11:59:00-05:00", nil, true),
    ("2026-11-04T12:01:00-05:00", nil, false),
    // A train running early comes into the window, and a late one leaves it.
    ("2026-11-04T13:00:00-05:00", "2026-11-04T11:30:00-05:00", true),
    ("2026-11-04T11:00:00-05:00", "2026-11-04T13:00:00-05:00", false),
    // An overdue train that hasn't departed stays.
    ("2026-11-03T22:00:00-05:00", "2026-11-04T05:00:00-05:00", true),
  ] as [(String, String?, Bool)])
func lookAhead(scheduled: String, estimate: String?, isShown: Bool) {
  let due = TrainStatusRows.due(
    [row(arriving: scheduled, estimate: estimate)], within: 6, of: beforeTheTrain)
  #expect(due.isEmpty != isShown)
}

@Test("Without a look-ahead, or without times, every row stays")
func lookAheadKeeps() {
  let tomorrow = row(arriving: "2026-11-05T09:07:00-05:00")
  #expect(TrainStatusRows.due([tomorrow], within: nil, of: beforeTheTrain) == [tomorrow])
  #expect(TrainStatusRows.due([sampleRow], within: 1, of: beforeTheTrain) == [sampleRow])
}

// MARK: - Model

@Test("The board shows rows as they come into the look-ahead")
func modelLookAhead() async throws {
  let later = row(arriving: "2026-11-04T13:00:00-05:00")
  let board = model(
    StubLoader(updates: [
      "ASD": .loaded(
        stationName: nil, rows: [later], timeZone: newYork, problem: nil,
        fetchedAt: beforeTheTrain)
    ]),
    lookAheadHours: 6)
  try await pump(board) { !board.rows.isEmpty }
  #expect(board.shownRows(now: beforeTheTrain).isEmpty)
  #expect(board.emptyMessage == "NO TRAINS IN THE NEXT 6 HOURS")
  #expect(board.shownRows(now: date("2026-11-04T07:30:00-05:00")) == [later])
}

@Test(
  "The empty board names the look-ahead only when it hid the trains",
  arguments: [(1, "NO TRAINS IN THE NEXT HOUR"), (nil, "NO ACTIVE TRAINS REPORTED")]
    as [(Int?, String)])
func lookAheadMessage(hours: Int?, expected: String) async throws {
  let tomorrow = row(arriving: "2026-11-05T09:07:00-05:00")
  let board = model(
    StubLoader(updates: [
      "ASD": .loaded(
        stationName: nil, rows: hours == nil ? [] : [tomorrow], timeZone: newYork,
        problem: nil, fetchedAt: beforeTheTrain)
    ]),
    lookAheadHours: hours)
  try await pump(board) { board.lastUpdatedAt != nil }
  #expect(board.emptyMessage == expected)
}

@Test("A refresh reaches the model through the frame update")
func refreshApplies() async throws {
  let board = model(
    StubLoader(updates: [
      "ASD": .loaded(
        stationName: nil, rows: [sampleRow], timeZone: newYork, problem: nil,
        fetchedAt: beforeTheTrain)
    ]))
  try await pump(board) { !board.rows.isEmpty }
  #expect(board.rows == [sampleRow])
  #expect(board.problem == nil)
  #expect(board.updateSummary.hasPrefix("UPDATED "))
}

@Test("Only the first refresh for a station may use the cache")
func firstRefreshReusesCache() async throws {
  let loader = GatedLoader()
  let board = model(loader)
  let loaded = BoardUpdate.loaded(
    stationName: nil, rows: [sampleRow], timeZone: newYork, problem: nil,
    fetchedAt: beforeTheTrain)

  board.update(now: beforeTheTrain)
  try await waitForRequests(loader, count: 1)
  await loader.releaseFirst(with: loaded)
  try await pump(board) { !board.rows.isEmpty }

  board.update(now: beforeTheTrain.addingTimeInterval(601))
  try await waitForRequests(loader, count: 1)
  await loader.releaseFirst(with: loaded)

  board.selectStation(code: "NYP", named: "STATION NYP")
  board.update(now: beforeTheTrain.addingTimeInterval(602))
  try await waitForRequests(loader, count: 1)

  #expect(await loader.maxAges == [600, nil, 600])
}

@Test("Cached data shows when it was fetched, and brings the next refresh closer")
func cachedDataIsDated() async throws {
  let loader = GatedLoader()
  let board = model(loader)
  let fetchedAt = beforeTheTrain.addingTimeInterval(-500)

  board.update(now: beforeTheTrain)
  try await waitForRequests(loader, count: 1)
  await loader.releaseFirst(
    with: .loaded(
      stationName: nil, rows: [sampleRow], timeZone: newYork, problem: nil,
      fetchedAt: fetchedAt))
  try await pump(board) { !board.rows.isEmpty }
  #expect(board.lastUpdatedAt == fetchedAt)
  #expect(board.updateSummary == "UPDATED 05:51")

  // Due 600 seconds after the data was fetched, not after this refresh started.
  board.update(now: beforeTheTrain.addingTimeInterval(99))
  try await Task.sleep(for: .milliseconds(100))
  #expect(await loader.waitingCount == 0)
  board.update(now: beforeTheTrain.addingTimeInterval(101))
  try await waitForRequests(loader, count: 1)
}

@Test("A failed refresh keeps the rows and says they are old")
func failureKeepsRows() async throws {
  let loader = GatedLoader()
  let board = model(loader)
  board.update(now: beforeTheTrain)
  try await waitForRequests(loader, count: 1)
  await loader.releaseFirst(
    with: .loaded(
      stationName: "ASHLAND, VA", rows: [sampleRow], timeZone: newYork, problem: nil,
      fetchedAt: beforeTheTrain))
  try await pump(board) { !board.rows.isEmpty }

  board.update(now: beforeTheTrain.addingTimeInterval(601))
  try await waitForRequests(loader, count: 1)
  await loader.releaseFirst(with: .failed(message: "AMTRAKER RETURNED HTTP 500"))
  try await pump(board, now: beforeTheTrain.addingTimeInterval(602)) { board.problem != nil }

  #expect(board.rows == [sampleRow])
  #expect(board.updateSummary == "AMTRAKER RETURNED HTTP 500  /  SHOWING DATA FROM 06:00")
  #expect(board.stationName == "ASHLAND, VA")
}

@Test("A typed station takes Amtraker's name when it loads")
func typedStationTakesName() async throws {
  let board = model(
    StubLoader(updates: [
      "NYP": .loaded(
        stationName: "NEW YORK PENN, NY", rows: [sampleRow], timeZone: newYork,
        problem: nil, fetchedAt: beforeTheTrain)
    ]))
  let choice = try #require(StationChoice(typedCode: "nyp"))
  board.selectStation(code: choice.code, named: choice.name)
  #expect(board.stationName == "STATION NYP")

  try await pump(board) { !board.rows.isEmpty }
  #expect(board.stationName == "NEW YORK PENN, NY")
}

@Test("A refresh without a usable name keeps the name on the board")
func missingNameKeepsCurrentName() async throws {
  let board = model(
    StubLoader(updates: [
      "ASD": .loaded(
        stationName: nil, rows: [sampleRow], timeZone: newYork, problem: nil,
        fetchedAt: beforeTheTrain)
    ]))
  try await pump(board) { !board.rows.isEmpty }
  #expect(board.stationName == "ASHLAND, VA")
}

@Test("A failed refresh leaves a typed station's placeholder name")
func failureKeepsPlaceholder() async throws {
  let board = model(StubLoader(updates: ["NYP": .failed(message: "AMTRAKER RETURNED HTTP 500")]))
  board.selectStation(code: "NYP", named: "STATION NYP")
  try await pump(board) { board.problem != nil }
  #expect(board.stationName == "STATION NYP")
}

@Test("A partly failed refresh shows the rows and names what is missing")
func partialFailureIsReported() async throws {
  let board = model(
    StubLoader(updates: [
      "ASD": .loaded(
        stationName: nil, rows: [sampleRow], timeZone: newYork, problem: "TRAIN 1124 UNAVAILABLE",
        fetchedAt: beforeTheTrain)
    ]))
  try await pump(board) { !board.rows.isEmpty }
  #expect(board.problem == "TRAIN 1124 UNAVAILABLE")
}

@Test("An unknown station clears the rows")
func unknownStationClearsRows() async throws {
  let board = model(StubLoader(updates: ["ASD": .stationNotFound(code: "ASD")]))
  try await pump(board) { board.problem != nil }
  #expect(board.rows.isEmpty)
  #expect(board.statusMessage == "STATION ASD NOT FOUND")
}

@Test("A result for the previous station is dropped")
func staleSelectionIsDropped() async throws {
  let loader = GatedLoader()
  let board = model(loader)
  board.update(now: beforeTheTrain)
  try await waitForRequests(loader, count: 1)

  board.selectStation(code: "SPB", named: "SPARTANBURG, SC")
  board.update(now: beforeTheTrain)
  try await waitForRequests(loader, count: 2)

  await loader.releaseFirst(
    with: .loaded(
      stationName: "ASHLAND, VA", rows: [sampleRow], timeZone: newYork, problem: nil,
      fetchedAt: beforeTheTrain))
  try await Task.sleep(for: .milliseconds(50))
  board.update(now: beforeTheTrain)
  #expect(board.rows.isEmpty)
  #expect(board.stationCode == "SPB")
  #expect(board.stationName == "SPARTANBURG, SC")
  #expect(board.lastUpdatedAt == nil)
}

@Test("Only one refresh runs at a time")
func refreshesDoNotOverlap() async throws {
  let loader = GatedLoader()
  let board = model(loader)
  board.update(now: beforeTheTrain)
  try await waitForRequests(loader, count: 1)

  board.update(now: beforeTheTrain.addingTimeInterval(601))
  board.update(now: beforeTheTrain.addingTimeInterval(1202))
  try await Task.sleep(for: .milliseconds(50))
  #expect(await loader.waitingCount == 1)
}

private func waitForRequests(_ loader: GatedLoader, count: Int) async throws {
  for _ in 0..<500 {
    if await loader.waitingCount == count { return }
    try await Task.sleep(for: .milliseconds(5))
  }
  Issue.record("The loader did not receive \(count) requests.")
}

// MARK: - Split-flap board

@Test("A new character flips across its full duration")
func tileFlips() {
  var board = SplitFlapBoard()
  board.show([["A"]], capacities: [1], at: 10)
  let tile = board.tile(row: 0, column: 0, index: 0)
  #expect(tile.character(at: 10) == " ")
  #expect(tile.progress(at: 10) == 0)
  #expect(tile.character(at: 10 + SplitFlapBoard.flipDuration / 2) == "A")
  #expect(tile.progress(at: 10 + SplitFlapBoard.flipDuration + 0.001) == 1)
}

@Test("Showing unchanged text restarts nothing")
func unchangedTextIsStable() {
  var board = SplitFlapBoard()
  board.show([["A"]], capacities: [1], at: 10)
  let tile = board.tile(row: 0, column: 0, index: 0)
  board.show([["A"]], capacities: [1], at: 99)
  #expect(board.tile(row: 0, column: 0, index: 0) == tile)
}

@Test("A settled tile does not flip when other tiles in its column change")
func onlyChangedTilesFlip() {
  var board = SplitFlapBoard()
  board.show([["AB"]], capacities: [2], at: 10)
  board.show([["AC"]], capacities: [2], at: 99)
  #expect(board.tile(row: 0, column: 0, index: 0).progress(at: 99) == 1)
  #expect(board.tile(row: 0, column: 0, index: 1).current == "B")
  #expect(board.tile(row: 0, column: 0, index: 1).target == "C")
}

@Test("A new train flips over what the row showed before")
func positionsOutliveTrains() {
  var board = SplitFlapBoard()
  board.show([["  :"]], capacities: [3], at: 10)
  board.show([["09:"]], capacities: [3], at: 99)
  let tile = board.tile(row: 0, column: 0, index: 0)
  #expect(tile.current == " ")
  #expect(tile.target == "0")
  #expect(board.tile(row: 0, column: 0, index: 2).character(at: 99) == ":")
}

@Test("An interrupted flip continues from what it shows")
func interruptedFlip() {
  var board = SplitFlapBoard()
  board.show([["A"]], capacities: [1], at: 10)
  board.show([["B"]], capacities: [1], at: 10 + SplitFlapBoard.flipDuration * 0.75)
  let tile = board.tile(row: 0, column: 0, index: 0)
  #expect(tile.current == "A")
  #expect(tile.target == "B")
}

@Test("Text is uppercased, cut to fit, and padded with blanks")
func textFits() {
  var board = SplitFlapBoard()
  board.show([["abc"]], capacities: [2], at: 0)
  #expect(board.tile(row: 0, column: 0, index: 0).target == "A")
  #expect(board.tile(row: 0, column: 0, index: 1).target == "B")
  #expect(board.tile(row: 0, column: 0, index: 2).target == " ")
}

@Test("Tiles that no longer fit are forgotten")
func removedTilesAreForgotten() {
  var board = SplitFlapBoard()
  board.show([["A"], ["B"]], capacities: [1], at: 0)
  board.show([["A"]], capacities: [1], at: 1)
  #expect(board.tile(row: 1, column: 0, index: 0) == FlapTile())
}

@Test(
  "Tile counts follow the column's width",
  arguments: [(20, 112, 8), (20, 70, 5), (22, 330, 22), (20, 0, 0), (20, 13, 1)])
func capacity(fontSize: Int, width: Int, expected: Int) {
  #expect(SplitFlapMetrics(fontSize: fontSize).capacity(forWidth: width) == expected)
}

// MARK: - Station choices

@Test(
  "Station headings combine Amtraker's name and state",
  arguments: [
    ("New York Penn", "NY", "NEW YORK PENN, NY"),
    ("Ashland", "VA", "ASHLAND, VA"),
    ("Pinehurst, NC", "NC", "PINEHURST, NC"),
    ("Saint-Maurice Rivière Boom", "", "SAINT-MAURICE RIVIÈRE BOOM"),
    ("  Quincy ", " il ", "QUINCY, IL"),
  ])
func stationHeadings(name: String, state: String, expected: String) {
  #expect(StationHeading.make(name: name, state: state) == expected)
}

@Test("A station with no state or name is handled")
func incompleteStationHeadings() {
  #expect(StationHeading.make(name: "Ottawa", state: nil) == "OTTAWA")
  #expect(StationHeading.make(name: "   ", state: "NY") == nil)
}

@Test(
  "Typed station codes are normalized",
  arguments: [("asd", "ASD"), ("  spb ", "SPB"), ("A1", "A1")])
func typedCodes(text: String, code: String) {
  #expect(StationChoice(typedCode: text)?.code == code)
}

@Test(
  "Text that cannot be a station code is refused",
  arguments: ["", "   ", "TOOLONG", "A-B", "É"])
func invalidCodes(text: String) {
  #expect(StationChoice(typedCode: text) == nil)
}

@Test("Preset buttons carry their station in their name")
func presetControls() {
  let choice = StationChoice(presetControl: "preset.ASD", name: "Ashland, VA")
  #expect(choice == StationChoice(presetControl: "preset.ASD", name: "Ashland, VA"))
  #expect(choice?.code == "ASD")
  #expect(StationChoice(presetControl: "cancel", name: "Cancel") == nil)
}

// MARK: - Command line

@Test("--station and -s take a station code", arguments: [["--station", "nyp"], ["-s", "NYP"]])
func stationOption(arguments: [String]) throws {
  #expect(try AmtrakStatusApp.parse(arguments).station?.uppercased() == "NYP")
}

@Test(
  "--hours takes a whole number of at least 1",
  arguments: [("6", true), ("0", false), ("-2", false), ("1.5", false)])
func hoursOption(value: String, isValid: Bool) {
  let parsed = try? AmtrakStatusApp.parse(["--hours", value])
  #expect((parsed != nil) == isValid)
}

@Test("--print and --verbose are off unless given")
func printAndVerboseFlags() throws {
  let plain = try AmtrakStatusApp.parse([])
  #expect(!plain.printsBoard && !plain.verbose)
  let both = try AmtrakStatusApp.parse(["--print", "-v"])
  #expect(both.printsBoard && both.verbose)
}

@Test("Printed boards are a header and one tab-separated line per row")
func printedBoard() throws {
  let rows = TrainStatusRows.make(from: [try train()], atStation: "ASD", staleTimes: [:])
  let lines = BoardText.lines(for: rows, timeZone: newYork, now: beforeTheTrain)
  #expect(lines.first == "time\tnumber\ttrain\tto\tearly\tlate")
  #expect(lines.count == 2)
  #expect(lines[1].split(separator: "\t", omittingEmptySubsequences: false).count == 6)
}

@Test("A tab inside a field cannot split it")
func printedTabs() {
  let row = TrainStatusRow(
    trainID: "67-3",
    scheduledArrival: ISO8601DateFormatter().date(from: "2026-11-04T09:07:00-05:00"),
    trainNum: "67", service: "Northeast\tRegional", destination: "Boston", punctuality: .onTime)
  #expect(
    BoardText.lines(for: [row], timeZone: newYork, now: beforeTheTrain)[1]
      == "09:07\t67\tNortheast Regional\tBoston\t\t")
}

@Test("--station refuses text that cannot be a station code")
func invalidStationOption() {
  #expect(throws: (any Error).self) { try AmtrakStatusApp.parse(["--station", "A-B"]) }
}

// MARK: - Interface documents

@Test("The board document has every control the screen uses")
func boardDocument() throws {
  let script = try InterfaceDocument.load(
    named: "board",
    requiring: TrainBoardScreen.requiredControls
  )
  #expect(script.ignoredAttributes.isEmpty)
  for column in BoardColumn.allCases {
    let control = try #require(script.control(named: column.rawValue))
    #expect(control.type == .region)
    #expect(script.style(for: control)?.fontSize != nil)
  }
}

@Test("The picker document has every control the picker uses")
func pickerDocument() throws {
  let script = try InterfaceDocument.load(
    named: "station-picker",
    requiring: StationPicker.requiredControls
  )
  #expect(script.ignoredAttributes.isEmpty)

  let presets = script.controls.filter { $0.name.hasPrefix("preset.") }
  #expect(presets.map(\.name).contains("preset.ASD"))
  for preset in presets {
    let code = String(preset.name.dropFirst("preset.".count))
    #expect(StationChoice(typedCode: code)?.code == code)
  }
}

@Test("A package's interface folder comes before SwiftPM's resource bundle")
func packagedDocumentIsPreferred() throws {
  let folder = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: folder) }
  let interface = folder.appendingPathComponent("Interface")
  try FileManager.default.createDirectory(at: interface, withIntermediateDirectories: true)
  let packaged = interface.appendingPathComponent("board.xml")
  try Data("<UIScript/>".utf8).write(to: packaged)

  #expect(InterfaceDocument.location(named: "board", packagedIn: folder)?.path == packaged.path)

  // The package has no picker document, so that lookup falls through to the bundle.
  let picker = try #require(InterfaceDocument.location(named: "station-picker", packagedIn: folder))
  #expect(picker.path != interface.appendingPathComponent("station-picker.xml").path)
  #expect(picker.lastPathComponent == "station-picker.xml")
}

@Test("A document that is nowhere has no location")
func unknownDocumentHasNoLocation() {
  #expect(InterfaceDocument.location(named: "nonexistent", packagedIn: nil) == nil)
}

@Test("A document missing a required control is refused")
func missingControlIsRefused() {
  #expect(
    throws: InterfaceDocumentError.missingControls(document: "board", names: ["nonexistent"])
  ) {
    try InterfaceDocument.load(named: "board", requiring: ["nonexistent"])
  }
}
