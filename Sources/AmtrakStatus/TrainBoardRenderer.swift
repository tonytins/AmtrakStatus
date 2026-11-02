import Foundation
import Hudini
import Raylib

private struct FlapTile {
  var current: Character = " "
  var target: Character = " "
  var startsAt: Double = 0
  var isAnimating = false
  var hasTarget = false
}

@MainActor
struct TrainBoardRenderer {
  let model: TrainBoardModel

  private let stationPicker = StationPicker()
  private var tiles: [String: FlapTile] = [:]
  private let animationDuration = 0.42
  private let background = Color(r: 17, g: 20, b: 23, a: 255)
  private let tileColor = Color(r: 30, g: 32, b: 38, a: 255)
  private let tileHighlight = Color(r: 44, g: 46, b: 52, a: 255)
  private let boardColor = Color(r: 8, g: 8, b: 8, a: 255)
  private let gold = Color(r: 238, g: 177, b: 72, a: 255)
  private let warmWhite = Color(r: 242, g: 232, b: 211, a: 255)
  private let boardWhite = Color.white
  private let muted = Color(r: 164, g: 155, b: 139, a: 255)
  private let headerDivider = Color(r: 76, g: 68, b: 58, a: 255)

  init(model: TrainBoardModel) {
    self.model = model
  }

  mutating func update(at time: Double) {
    var openedPicker = false
    if !stationPicker.isOpen,
      IsMouseButtonPressed(.left),
      CheckCollisionPointRec(GetMousePosition(), stationTitleBounds)
    {
      stationPicker.open()
      openedPicker = true
    }

    if !openedPicker, let choice = stationPicker.update() {
      let model = model
      Task {
        await model.selectStation(code: choice.code, named: choice.name.uppercased())
      }
    }

    let columns = model.rows.map { row in
      [
        row.scheduledTime,
        row.trainNum,
        row.service,
        row.destination,
        row.earlyDelay,
        row.lateDelay,
      ]
    }

    for (rowIndex, row) in model.rows.enumerated() {
      let values = columns[rowIndex]
      for (columnIndex, value) in values.enumerated() {
        let characters = Array(value.uppercased())
        let capacity = Self.characterCapacities[columnIndex]

        for tileIndex in 0..<capacity {
          let character = tileIndex < characters.count ? characters[tileIndex] : " "
          let key = "\(row.id)-\(columnIndex)-\(tileIndex)"
          var tile = tiles[key, default: FlapTile()]

          if !tile.hasTarget || tile.target != character {
            tile.target = character
            tile.startsAt =
              time
              + Double(rowIndex) * 0.18
              + Double(columnIndex) * 0.1
              + Double(tileIndex) * 0.018
            tile.isAnimating = tile.current != character
            tile.hasTarget = true
          }

          if tile.isAnimating && time >= tile.startsAt + animationDuration {
            tile.current = tile.target
            tile.isAnimating = false
          }

          tiles[key] = tile
        }
      }
    }
  }

  func draw() {
    let width = Int(GetScreenWidth())
    let height = Int(GetScreenHeight())
    ClearBackground(background)

    drawHeader(width: width)
    let time = Date.timeIntervalSinceReferenceDate
    drawBoard(width: width, height: height, time: time)
    drawFooter(width: width, height: height)
    stationPicker.draw()
  }

  private var stationTitleBounds: Rectangle {
    Rectangle(x: 28, y: 48, width: 500, height: 46)
  }

  private func drawHeader(width: Int) {
    DrawText("AMTRAK", 32, 24, 18, gold)
    DrawText(model.stationName, 32, 54, 34, warmWhite)
    DrawText("STATION \(model.stationCode)  /  LIVE TRAIN INFORMATION", 34, 96, 14, muted)

    let clock = model.localTime
    DrawText("LOCAL TIME", width - 210, 28, 12, muted)
    DrawText(clock, width - 210, 48, 28, gold)
    DrawLine(32, 124, width - 32, 124, headerDivider)
  }

  private func drawBoard(width: Int, height: Int, time: Double) {
    let left = 16
    let top = 144
    let boardWidth = max(0, width - left * 2)
    let boardBottom = max(top + 128, height - 90)
    let boardHeight = boardBottom - top
    let headingHeight = 38
    let rowHeight = 60

    DrawRectangle(left, top, boardWidth, boardHeight, boardColor)

    let weights = [0.12, 0.12, 0.27, 0.29, 0.1, 0.1]
    let columnWidths = weights.map { Int(Double(boardWidth) * $0) }
    let headers = ["SCHED. TIME", "NUMBER", "TRAIN", "TO", "(E)ARLY", "(L)ATE"]
    var x = left
    for (index, title) in headers.enumerated() {
      DrawText(title, x + 5, top + 11, 14, boardWhite)
      x += columnWidths[index]
    }
    DrawLine(left, top + headingHeight, left + boardWidth, top + headingHeight, muted)

    let rowsTop = top + headingHeight + 4
    let visibleRows = max(1, (boardHeight - headingHeight) / rowHeight)
    for rowIndex in 0..<visibleRows {
      let rowTop = rowsTop + rowIndex * rowHeight
      guard rowTop + rowHeight <= boardBottom else { break }

      guard rowIndex < model.rows.count else {
        drawEmptyRow(rowIndex, x: left, y: rowTop, columnWidths: columnWidths, time: time)
        continue
      }

      let row = model.rows[rowIndex]
      let values = [
        row.scheduledTime,
        row.trainNum,
        row.service,
        row.destination,
        row.earlyDelay,
        row.lateDelay,
      ]

      var columnX = left
      for (columnIndex, value) in values.enumerated() {
        drawFlapText(
          value,
          rowKey: row.id,
          columnIndex: columnIndex,
          x: columnX + 3,
          y: rowTop,
          width: columnWidths[columnIndex] - 6,
          height: 48,
          fontSize: columnIndex == 2 || columnIndex == 3 ? 22 : 20,
          time: time
        )
        columnX += columnWidths[columnIndex]
      }

      DrawLine(left, rowTop + rowHeight - 3, left + boardWidth, rowTop + rowHeight - 3, tileColor)
    }

    if model.rows.isEmpty {
      DrawText(model.statusMessage, left + 6, rowsTop + 12, 16, boardWhite)
    }
  }

  private func drawEmptyRow(
    _ rowIndex: Int,
    x: Int,
    y: Int,
    columnWidths: [Int],
    time: Double
  ) {
    let capacities = Self.characterCapacities
    var columnX = x
    for columnIndex in capacities.indices {
      drawFlapText(
        columnIndex == 0 ? "  :  " : "",
        rowKey: "empty-\(rowIndex)",
        columnIndex: columnIndex,
        x: columnX + 3,
        y: y,
        width: columnWidths[columnIndex] - 6,
        height: 48,
        fontSize: 20,
        time: time
      )
      columnX += columnWidths[columnIndex]
    }
    DrawLine(x, y + 57, x + columnWidths.reduce(0, +), y + 57, tileColor)
  }

  private func drawFooter(width: Int, height: Int) {
    let update = model.lastUpdatedTime.map { "UPDATED \($0)" } ?? "WAITING FOR FIRST UPDATE"
    let version = "VERSION \(GitVersion.current.version)"
    DrawText(update, 32, height - 46, 13, muted)
    DrawText(version, width - MeasureText(version, 13) - 32, height - 46, 13, gold)
    DrawText("DATA BY AMTRAKER  /  NOT AFFILIATED WITH AMTRAK", 32, height - 25, 10, muted)
  }

  private func drawFlapText(
    _ value: String,
    rowKey: String,
    columnIndex: Int,
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    fontSize: Int,
    time: Double
  ) {
    guard width > 0, height > 0 else { return }
    let gap = 2
    let cellWidth = max(12, fontSize * 3 / 5)
    let capacity = Self.characterCapacities[columnIndex]
    let characters = Array(value.uppercased().prefix(capacity))
    let cellHeight = height - 2
    let topHeight = cellHeight / 2
    let drawFontSize = min(fontSize, max(8, cellHeight - 6))

    for tileIndex in 0..<capacity {
      let cellX = x + tileIndex * (cellWidth + gap)
      guard cellX + cellWidth <= x + width else { break }

      let key = "\(rowKey)-\(columnIndex)-\(tileIndex)"
      let tile = tiles[key, default: FlapTile()]
      DrawRectangle(cellX, y, cellWidth, topHeight, tileColor)
      DrawRectangle(cellX, y + topHeight, cellWidth, cellHeight - topHeight, tileColor)

      let progress: Double
      if tile.isAnimating {
        progress = min(1, max(0, (time - tile.startsAt) / animationDuration))
      } else {
        progress = 1
      }
      let displayedCharacter: Character
      if tile.hasTarget {
        displayedCharacter = progress >= 0.5 ? tile.target : tile.current
      } else {
        displayedCharacter = tileIndex < characters.count ? characters[tileIndex] : " "
      }
      if displayedCharacter != " " {
        let glyph = String(displayedCharacter)
        let glyphWidth = MeasureText(glyph, drawFontSize)
        DrawText(
          glyph,
          cellX + (cellWidth - glyphWidth) / 2,
          y + (cellHeight - drawFontSize) / 2,
          drawFontSize,
          boardWhite
        )
      }

      drawFlipShutter(
        x: cellX,
        y: y + topHeight,
        width: cellWidth,
        height: topHeight,
        progress: progress,
        isAnimating: tile.isAnimating && time >= tile.startsAt
      )
      DrawLine(cellX, y + topHeight, cellX + cellWidth, y + topHeight, background)
    }
  }

  private func drawFlipShutter(
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    progress: Double,
    isAnimating: Bool
  ) {
    guard isAnimating else { return }
    let foldProgress = progress < 0.5 ? progress * 2 : (1 - progress) * 2
    let shutterHeight = max(1, Int(Double(height) * (1 - foldProgress)))
    let shutterY = progress < 0.5 ? y - shutterHeight : y
    DrawRectangle(x, shutterY, width, shutterHeight, tileHighlight)
    DrawLine(x, shutterY + shutterHeight, x + width, shutterY + shutterHeight, background)
  }

  private static let characterCapacities = [5, 5, 17, 18, 6, 6]
}
