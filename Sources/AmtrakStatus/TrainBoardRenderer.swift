import AmtrakClient
import Raylib

@MainActor
struct TrainBoardRenderer {
  let model: TrainBoardModel

  private let background = Color(r: 17, g: 20, b: 23, a: 255)
  private let boardColor = Color(r: 35, g: 31, b: 26, a: 255)
  private let flapTop = Color(r: 49, g: 46, b: 41, a: 255)
  private let flapBottom = Color(r: 28, g: 27, b: 25, a: 255)
  private let gold = Color(r: 238, g: 177, b: 72, a: 255)
  private let warmWhite = Color(r: 242, g: 232, b: 211, a: 255)
  private let muted = Color(r: 164, g: 155, b: 139, a: 255)
  private let divider = Color(r: 76, g: 68, b: 58, a: 255)

  func draw() {
    let width = Int(GetScreenWidth())
    let height = Int(GetScreenHeight())
    ClearBackground(background)

    drawHeader(width: width)
    drawBoard(width: width, height: height)
    drawFooter(width: width, height: height)
  }

  private func drawHeader(width: Int) {
    DrawText("AMTRAK", 32, 24, 18, gold)
    DrawText("ASHLAND, VIRGINIA", 32, 54, 34, warmWhite)
    DrawText("STATION ASD  /  LIVE TRAIN INFORMATION", 34, 96, 14, muted)

    let clock = model.localTime
    DrawText("LOCAL TIME", width - 210, 28, 12, muted)
    DrawText(clock, width - 210, 48, 28, gold)

    DrawLine(32, 124, width - 32, 124, divider)
  }

  private func drawBoard(width: Int, height: Int) {
    let left = 32
    let top = 144
    let boardWidth = max(0, width - left * 2)
    let boardBottom = max(top + 128, height - 90)
    let boardHeight = boardBottom - top
    let headingHeight = 38
    let rowHeight = 64

    DrawRectangle(left, top, boardWidth, boardHeight, boardColor)
    DrawRectangle(left, top, boardWidth, headingHeight, Color.darkBrown)

    let columnWidths = [0.12, 0.10, 0.16, 0.18, 0.19, 0.17, 0.08].map {
      Int(Double(boardWidth) * $0)
    }
    let headers = ["ARRIVAL", "TRAIN", "SERVICE", "FROM", "TO", "STATUS", "TRACK"]
    var x = left
    for (index, title) in headers.enumerated() {
      DrawText(title, x + 8, top + 12, 11, gold)
      x += columnWidths[index]
    }

    let rowsTop = top + headingHeight
    let visibleRows = max(1, (boardHeight - headingHeight) / rowHeight)
    for index in 0..<visibleRows {
      let rowTop = rowsTop + index * rowHeight
      guard rowTop + rowHeight <= boardBottom else { break }

      if index.isMultiple(of: 2) {
        DrawRectangle(left, rowTop, boardWidth, rowHeight, Color(r: 41, g: 37, b: 32, a: 255))
      }

      DrawLine(left, rowTop + rowHeight - 1, left + boardWidth, rowTop + rowHeight - 1, divider)

      guard index < model.rows.count else { continue }
      draw(row: model.rows[index], x: left, y: rowTop, columnWidths: columnWidths)
    }

    if model.rows.isEmpty {
      drawFlapText(
        model.statusMessage,
        x: left + 18,
        y: rowsTop + 18,
        width: boardWidth - 36,
        height: 36,
        fontSize: 20,
        ink: model.statusMessage.hasPrefix("UPDATE FAILED") ? Color.red : muted
      )
    }
  }

  private func draw(row: TrainStatusRow, x startX: Int, y: Int, columnWidths: [Int]) {
    var x = startX
    let values = [
      row.arrivalTime,
      row.trainNum,
      row.service,
      row.origin,
      row.destination,
    ]

    for (index, value) in values.enumerated() {
      drawFlapText(
        value,
        x: x + 5,
        y: y + 10,
        width: columnWidths[index] - 10,
        height: 44,
        fontSize: 15,
        ink: warmWhite
      )
      x += columnWidths[index]
    }

    drawStatus(row, x: x + 5, y: y + 5, width: columnWidths[5] - 10)
    x += columnWidths[5]

    drawFlapText(
      row.track.isEmpty ? "--" : row.track,
      x: x + 5,
      y: y + 10,
      width: columnWidths[6] - 10,
      height: 44,
      fontSize: 15,
      ink: warmWhite
    )
  }

  private func drawStatus(_ row: TrainStatusRow, x: Int, y: Int, width: Int) {
    let presence: String
    switch row.presence {
    case .enroute:
      presence = "EN ROUTE"
    case .station:
      presence = "AT STATION"
    case .departed:
      presence = "DEPARTED"
    case .unknown:
      presence = "UNKNOWN"
    }

    let punctuality = row.punctuality.description.uppercased()
    drawFlapText(
      presence,
      x: x,
      y: y,
      width: width,
      height: 25,
      fontSize: 12,
      ink: presenceColor(row.presence)
    )
    drawFlapText(
      punctuality,
      x: x,
      y: y + 27,
      width: width,
      height: 25,
      fontSize: 11,
      ink: punctualityColor(row.punctuality)
    )
  }

  private func drawFooter(width: Int, height: Int) {
    let update = model.lastUpdatedTime.map { "UPDATED \($0)" } ?? "WAITING FOR FIRST UPDATE"
    let refresh = model.statusMessage
    DrawText(update, 32, height - 46, 13, muted)
    DrawText(refresh, width - MeasureText(refresh, 13) - 32, height - 46, 13, gold)
    DrawText("DATA BY AMTRAKER  /  NOT AFFILIATED WITH AMTRAK", 32, height - 25, 10, muted)
  }

  private func drawFlapText(
    _ value: String,
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    fontSize: Int,
    ink: Color
  ) {
    guard width > 0, height > 0 else { return }
    let gap = 2
    let cellWidth = max(12, fontSize * 3 / 5)
    let characterLimit = max(1, (width + gap) / (cellWidth + gap))
    let characters = Array(value.uppercased().prefix(characterLimit))
    let cellHeight = height - 2
    let topHeight = cellHeight / 2
    let drawFontSize = min(fontSize, max(8, cellHeight - 6))

    for (index, character) in characters.enumerated() {
      let cellX = x + index * (cellWidth + gap)
      DrawRectangle(cellX, y, cellWidth, topHeight, flapTop)
      DrawRectangle(cellX, y + topHeight, cellWidth, cellHeight - topHeight, flapBottom)
      DrawLine(cellX, y + topHeight, cellX + cellWidth, y + topHeight, background)

      let glyph = String(character)
      guard character != " " else { continue }
      let glyphWidth = MeasureText(glyph, drawFontSize)
      DrawText(
        glyph,
        cellX + (cellWidth - glyphWidth) / 2,
        y + (cellHeight - drawFontSize) / 2,
        drawFontSize,
        ink
      )
    }
  }

  private func presenceColor(_ status: StationStatus) -> Color {
    switch status {
    case .enroute:
      return Color.skyBlue
    case .station:
      return Color.green
    case .departed:
      return muted
    case .unknown:
      return Color.orange
    }
  }

  private func punctualityColor(_ status: LateTrain) -> Color {
    switch status {
    case .onTime:
      return Color.green
    case .early:
      return Color.skyBlue
    case .late:
      return Color.red
    case .unknown:
      return muted
    }
  }
}
