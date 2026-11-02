import Foundation
import ArgumentParser
import Logging
import Raylib

@main
struct AmtrakStatusApp: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "amtrak-status",
    abstract: "Show Amtrak train status for a selected station."
  )

  @Option(
    name: .long,
    help: "Minimum seconds between API refreshes. Must be at least 600."
  )
  var refreshInterval = 600

  @MainActor
  mutating func run() async throws {
    guard refreshInterval >= 600 else {
      throw ValidationError("Refresh interval must be at least 600 seconds.")
    }

    LoggingSystem.bootstrap(StreamLogHandler.standardError)

    SetConfigFlags([.vsyncHint, .windowResizable])
    InitWindow(1200, 760, "Amtrak Status - Ashland, VA")
    defer { CloseWindow() }

    SetExitKey(.null)
    SetTargetFPS(60)

    let board = TrainBoardModel()
    var renderer = TrainBoardRenderer(model: board)
    Task {
      await board.refresh()
    }

    var nextRefresh = Date().addingTimeInterval(TimeInterval(refreshInterval))

    while !WindowShouldClose() {
      if Date() >= nextRefresh {
        nextRefresh = Date().addingTimeInterval(TimeInterval(refreshInterval))
        Task {
          await board.refresh()
        }
      }

      renderer.update(at: Date.timeIntervalSinceReferenceDate)
      BeginDrawing()
      renderer.draw()
      EndDrawing()

      await Task.yield()
    }
  }
}
