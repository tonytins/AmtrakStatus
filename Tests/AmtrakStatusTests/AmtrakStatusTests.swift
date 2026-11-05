import AmtrakClient
import Foundation
import Hudini
import Testing

@testable import AmtrakStatus

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

private func rows(
  _ trains: [Train],
  staleTimes: [String: TimeInterval] = [:],
  now: Date = beforeTheTrain
) -> [TrainStatusRow] {
  TrainStatusRows.make(
    from: trains,
    atStation: "ASD",
    staleTimes: staleTimes,
    timeZone: newYork,
    now: now
  )
}

private struct StubLoader: TrainStatusLoading {
  let updates: [String: BoardUpdate]

  func update(forStation code: String) async -> BoardUpdate {
    updates[code] ?? .failed(message: "NO STUB")
  }
}

/// Holds a station's result back until the test releases it.
private actor GatedLoader: TrainStatusLoading {
  private var waiting: [CheckedContinuation<BoardUpdate, Never>] = []

  func update(forStation code: String) async -> BoardUpdate {
    await withCheckedContinuation { waiting.append($0) }
  }

  var waitingCount: Int { waiting.count }

  func releaseFirst(with update: BoardUpdate) {
    waiting.removeFirst().resume(returning: update)
  }
}

private func model(_ loader: any TrainStatusLoading) -> TrainBoardModel {
  TrainBoardModel(
    stationCode: "ASD",
    stationName: "ASHLAND, VA",
    refreshInterval: 600,
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

// MARK: - Rows

@Test("Rows use only the characters the board's font can draw")
func boardTimeIsASCII() throws {
  let row = try #require(rows([train()]).first)
  let time = BoardRowText(timeZone: newYork, dates: BoardDateFormatting()).value(of: .time, in: row)
  #expect(time == " 9:07 AM")
  #expect(time.utf8.count == time.count)

  let clock = BoardDateFormatting().time(of: beforeTheTrain, in: newYork)
  #expect(clock == "6:00 AM")
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
  let text = BoardRowText(timeZone: newYork, dates: BoardDateFormatting())
  #expect(text.value(of: .time, in: sampleRow) == "--")
}

@Test("Times are written in the station's time zone")
func timesUseStationZone() throws {
  let row = try #require(rows([train()]).first)
  let chicago = BoardRowText(
    timeZone: TimeZone(identifier: "America/Chicago"), dates: BoardDateFormatting())
  #expect(chicago.value(of: .time, in: row) == " 8:07 AM")
}

@Test("Trains that share a time keep their order between refreshes")
func rowOrderIsStable() throws {
  let first = try train(id: "1-1", number: "1")
  let second = try train(id: "2-1", number: "2")
  #expect(rows([first, second]).map(\.trainID) == ["1-1", "2-1"])
  #expect(rows([second, first]).map(\.trainID) == ["1-1", "2-1"])
}

@Test("Trains that departed on an earlier day and silent trains are left out")
func staleTrainsAreLeftOut() throws {
  let dayAfter = beforeTheTrain.addingTimeInterval(60 * 60 * 24)
  let departed = try train(dep: "\"2026-11-04T09:08:00-05:00\"", status: "Departed")
  #expect(rows([departed]).count == 1)
  #expect(rows([departed], now: dayAfter).isEmpty)

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

// MARK: - Model

@Test("A refresh reaches the model through the frame update")
func refreshApplies() async throws {
  let board = model(
    StubLoader(updates: [
      "ASD": .loaded(stationName: nil, rows: [sampleRow], timeZone: newYork, unavailableTrains: [])
    ]))
  try await pump(board) { !board.rows.isEmpty }
  #expect(board.rows == [sampleRow])
  #expect(board.problem == nil)
  #expect(board.updateSummary.hasPrefix("UPDATED "))
}

@Test("A failed refresh keeps the rows and says they are old")
func failureKeepsRows() async throws {
  let loader = GatedLoader()
  let board = model(loader)
  board.update(now: beforeTheTrain)
  try await waitForRequests(loader, count: 1)
  await loader.releaseFirst(
    with: .loaded(
      stationName: "ASHLAND, VA", rows: [sampleRow], timeZone: newYork, unavailableTrains: []))
  try await pump(board) { !board.rows.isEmpty }

  board.update(now: beforeTheTrain.addingTimeInterval(601))
  try await waitForRequests(loader, count: 1)
  await loader.releaseFirst(with: .failed(message: "AMTRAKER RETURNED HTTP 500"))
  try await pump(board, now: beforeTheTrain.addingTimeInterval(602)) { board.problem != nil }

  #expect(board.rows == [sampleRow])
  #expect(board.updateSummary == "AMTRAKER RETURNED HTTP 500  /  SHOWING DATA FROM 6:00 AM")
  #expect(board.stationName == "ASHLAND, VA")
}

@Test("A typed station takes Amtraker's name when it loads")
func typedStationTakesName() async throws {
  let board = model(
    StubLoader(updates: [
      "NYP": .loaded(
        stationName: "NEW YORK PENN, NY", rows: [sampleRow], timeZone: newYork,
        unavailableTrains: [])
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
      "ASD": .loaded(stationName: nil, rows: [sampleRow], timeZone: newYork, unavailableTrains: [])
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
        stationName: nil, rows: [sampleRow], timeZone: newYork, unavailableTrains: ["1124"])
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
      stationName: "ASHLAND, VA", rows: [sampleRow], timeZone: newYork, unavailableTrains: []))
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

@Test("--print and --verbose are off unless given")
func printAndVerboseFlags() throws {
  let plain = try AmtrakStatusApp.parse([])
  #expect(!plain.printsBoard && !plain.verbose)
  let both = try AmtrakStatusApp.parse(["--print", "-v"])
  #expect(both.printsBoard && both.verbose)
}

@Test("Printed boards are a header and one tab-separated line per row")
func printedBoard() throws {
  let rows = TrainStatusRows.make(
    from: [try train()],
    atStation: "ASD",
    staleTimes: [:],
    timeZone: newYork,
    now: beforeTheTrain
  )
  let lines = BoardText.lines(for: rows, timeZone: newYork)
  #expect(lines.first == "time\tnumber\ttrain\tto\tearly\tlate")
  #expect(lines.count == 2)
  #expect(lines[1].split(separator: "\t", omittingEmptySubsequences: false).count == 6)
}

@Test("A tab inside a field cannot split it, and padding is dropped")
func printedTabs() {
  let row = TrainStatusRow(
    trainID: "67-3",
    scheduledArrival: ISO8601DateFormatter().date(from: "2026-11-04T09:07:00-05:00"),
    trainNum: "67", service: "Northeast\tRegional", destination: "Boston", punctuality: .onTime)
  #expect(
    BoardText.lines(for: [row], timeZone: newYork)[1]
      == "9:07 AM\t67\tNortheast Regional\tBoston\t\t")
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
