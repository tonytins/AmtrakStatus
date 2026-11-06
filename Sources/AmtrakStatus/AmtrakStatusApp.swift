import AmtrakClient
import ArgumentParser
import Foundation
import Logging
import Raylib

/// The entry point. It stays synchronous so the render loop keeps the process's main thread.
///
/// An OpenGL context belongs to one thread. An async `@main` hands the main actor to libdispatch
/// on Linux, whose worker threads take turns running it. Frames on a thread without the context
/// draw nothing and still swap buffers, which makes the window flicker.
@main
struct AmtrakStatusApp: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "amtrak-status",
    abstract: "Show Amtrak train status for a selected station.",
    version: "\(GitVersion.major).\(GitVersion.minor).\(GitVersion.patch)"
  )

  @Option(
    name: .long,
    help: "Minimum seconds between API refreshes. Must be at least 600."
  )
  var refreshInterval = 600

  @Option(
    name: [.short, .long],
    help: "The station code to open on, such as NYP. Defaults to Ashland, VA (ASD)."
  )
  var station: String?

  @Option(
    name: .long,
    help: "Only show trains due within this many hours. Late trains stay until they depart."
  )
  var hours: Int?

  @Flag(
    name: .long,
    help: "Check the interface documents, print where they were found, and exit without a window."
  )
  var checkInterface = false

  @Flag(
    name: .customLong("print"),
    help: "Print the station's trains as tab-separated text and exit without a window."
  )
  var printsBoard = false

  @Flag(
    name: [.short, .long],
    help: "Log each request and refresh, and Raylib's startup details."
  )
  var verbose = false

  func validate() throws {
    guard refreshInterval >= 600 else {
      throw ValidationError("Refresh interval must be at least 600 seconds.")
    }
    if let hours, hours < 1 {
      throw ValidationError("Hours must be at least 1.")
    }
    if let station, StationChoice(typedCode: station) == nil {
      throw ValidationError("Station codes use up to 5 letters and numbers, such as NYP.")
    }
  }

  /// The station the board opens on.
  private var startingStation: StationChoice {
    station.flatMap(StationChoice.init(typedCode:)) ?? .ashland
  }

  func run() throws {
    precondition(Thread.isMainThread, "The render loop must run on the main thread.")

    let logLevel: Logger.Level = verbose ? .info : .warning
    LoggingSystem.bootstrap { label in
      var handler = StreamLogHandler.standardError(label: label)
      handler.logLevel = logLevel
      return handler
    }
    SetTraceLogLevel(verbose ? .info : .warning)
    let loader = AmtrakerStatusLoader(cache: Self.openCache())

    if printsBoard {
      try printBoard(with: loader)
      return
    }

    let boardScript = try InterfaceDocument.load(
      named: "board",
      requiring: TrainBoardScreen.requiredControls
    )
    let pickerScript = try InterfaceDocument.load(
      named: "station-picker",
      requiring: StationPicker.requiredControls
    )
    if checkInterface {
      for name in ["board", "station-picker"] {
        print(InterfaceDocument.location(named: name)?.path ?? "")
      }
      return
    }

    let start = startingStation
    let model = TrainBoardModel(
      stationCode: start.code,
      stationName: start.name,
      refreshInterval: TimeInterval(refreshInterval),
      lookAheadHours: hours,
      loader: loader
    )

    SetConfigFlags([.vsyncHint, .windowResizable, .msaa4xHint])
    InitWindow(
      Int(boardScript.window.size.width),
      Int(boardScript.window.size.height),
      "Amtrak Status - \(model.stationName)"
    )
    defer { CloseWindow() }

    if let minimumSize = boardScript.window.minSize {
      SetWindowMinSize(Int(minimumSize.width), Int(minimumSize.height))
    }
    // Escape closes the picker when it is open, and the screen quits otherwise.
    SetExitKey(.null)
    SetTargetFPS(60)

    let screen = TrainBoardScreen(
      model: model,
      script: boardScript,
      picker: StationPicker(script: pickerScript)
    )

    while !WindowShouldClose(), !screen.shouldQuit {
      let time = GetTime()
      screen.update(at: time, now: Date())
      BeginDrawing()
      screen.draw(at: time)
      EndDrawing()
    }
  }

  /// Loads the starting station once and writes its rows to standard output.
  private func printBoard(with loader: AmtrakerStatusLoader) throws {
    let code = startingStation.code
    let maxAge = TimeInterval(refreshInterval)
    let results = Mailbox<BoardUpdate>()
    let finished = DispatchSemaphore(value: 0)
    Task {
      results.deliver(await loader.update(forStation: code, reusingCacheWithin: maxAge))
      finished.signal()
    }
    finished.wait()

    switch results.collect().first {
    case .loaded(_, let rows, let timeZone, let problem, let fetchedAt, _):
      let now = Date()
      let shown = TrainStatusRows.due(rows, within: hours, of: now)
      for line in BoardText.lines(for: shown, timeZone: timeZone, now: now) {
        print(line)
      }
      if let problem {
        let fetched = ISO8601DateFormatter().string(from: fetchedAt)
        Self.printError("\(problem) (data fetched \(fetched))")
      }
    case .stationNotFound(let code):
      Self.printError("Amtraker does not know station \(code).")
      throw ExitCode.failure
    case .failed(let message):
      Self.printError(message)
      throw ExitCode.failure
    case nil:
      throw ExitCode.failure
    }
  }

  /// How long cached responses are kept before they are deleted at startup.
  private static let cacheLifetime: TimeInterval = 2 * 24 * 60 * 60

  /// Returns the response cache after deleting old responses, or `nil` when this system has no
  /// cache folder. The app works without one, fetching everything each launch.
  private static func openCache() -> ResponseCache? {
    let logger = Logger(label: "com.tonybark.AmtrakStatus")
    guard let directory = ResponseCache.standardDirectory(named: "AmtrakStatus") else {
      logger.warning("This system has no cache folder, so nothing will be cached")
      return nil
    }
    let cache = ResponseCache(directory: directory)
    do {
      let removed = try cache.removeEntries(fetchedBefore: Date() - cacheLifetime)
      logger.info("Using the cache in \(directory.path), deleted \(removed) old responses")
    } catch {
      logger.warning("Could not delete old cached responses: \(error.localizedDescription)")
    }
    return cache
  }

  private static func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
  }
}
