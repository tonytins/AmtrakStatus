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
    abstract: "Show Amtrak train status for a selected station."
  )

  @Option(
    name: .long,
    help: "Minimum seconds between API refreshes. Must be at least 600."
  )
  var refreshInterval = 600

  func validate() throws {
    guard refreshInterval >= 600 else {
      throw ValidationError("Refresh interval must be at least 600 seconds.")
    }
  }

  func run() throws {
    precondition(Thread.isMainThread, "The render loop must run on the main thread.")

    LoggingSystem.bootstrap(StreamLogHandler.standardError)

    let boardScript = try InterfaceDocument.load(
      named: "board",
      requiring: TrainBoardScreen.requiredControls
    )
    let pickerScript = try InterfaceDocument.load(
      named: "station-picker",
      requiring: StationPicker.requiredControls
    )
    let model = TrainBoardModel(
      stationCode: "ASD",
      stationName: "ASHLAND, VA",
      refreshInterval: TimeInterval(refreshInterval),
      loader: AmtrakerStatusLoader()
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
}
