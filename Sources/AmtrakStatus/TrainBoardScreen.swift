import Foundation
import Hudini
import Raylib

/// Connects the model to `board.uix`: it fills the document's text controls, draws split-flap
/// tiles into its regions, and handles the board's input.
final class TrainBoardScreen {
  /// The controls the screen depends on.
  static let requiredControls =
    ["stationName", "stationButton", "stationDetail", "clock", "rows", "statusMessage"]
    + ["updateSummary", "version"]
    + BoardColumn.allCases.map(\.rawValue)

  private let model: TrainBoardModel
  private let script: UIScript
  private let view: UIScriptView
  private let picker: StationPicker
  private let windowManager = WindowManager()
  private let renderers: [SplitFlapRenderer]
  private let rowDivider: Color
  private let dates = BoardDateFormatting()
  private var board = SplitFlapBoard()
  private var rowCount = 1
  private var scrollOffset = 0
  /// How many trains the model had last frame, which bounds this frame's scrolling input.
  private var shownRowTotal = 0
  private var shownStationName: String?

  /// Whether the user asked to quit this frame.
  private(set) var shouldQuit = false

  /// Creates the screen, drawing its text in `textFont` and its split-flap tiles in
  /// `boardFont`, or raylib's font for either that is `nil`. Call this after `InitWindow`.
  init(
    model: TrainBoardModel,
    script: UIScript,
    picker: StationPicker,
    textFont: Font?,
    boardFont: Font?
  ) {
    self.model = model
    self.script = script
    self.picker = picker
    view = UIScriptView(script: script, theme: InterfaceTheme(font: textFont))
    renderers = BoardColumn.allCases.map { column in
      SplitFlapRenderer(
        style: script.control(named: column.rawValue).flatMap(script.style(for:)),
        font: boardFont
      )
    }
    rowDivider =
      script.control(named: "rows").flatMap(script.style(for:))?.borderColor
      ?? Color(r: 30, g: 32, b: 38, a: 255)
  }

  func update(at time: Double, now: Date) {
    // Input goes first, scrolling within last frame's limit, so a station chosen now shows its
    // own rows this frame. The rows and row count are read after the model and window update,
    // and the offset is clamped again in case either changed.
    handleInput(maxOffset: Self.maxScrollOffset(totalRows: shownRowTotal, rowCount: rowCount))
    model.update(now: now)
    view.setWindowSize(Vector2(x: Float(GetScreenWidth()), y: Float(GetScreenHeight())))

    let rows = model.shownRows(now: now)
    let rowsHeight = view.bounds(named: "rows", at: .zero)?.height ?? 0
    rowCount = SplitFlapMetrics.rowCount(forHeight: Int(rowsHeight))
    shownRowTotal = rows.count
    scrollOffset = Self.clampScrollOffset(scrollOffset, totalRows: rows.count, rowCount: rowCount)
    showModel(now: now, hasRows: !rows.isEmpty, totalRows: rows.count)
    showRows(rows, at: time, now: now)
  }

  /// The furthest the board can scroll: far enough that the last train fills the bottom row.
  static func maxScrollOffset(totalRows: Int, rowCount: Int) -> Int {
    max(0, totalRows - max(1, rowCount))
  }

  /// Keeps `offset` between the first train and `maxScrollOffset(totalRows:rowCount:)`.
  static func clampScrollOffset(_ offset: Int, totalRows: Int, rowCount: Int) -> Int {
    min(max(0, offset), maxScrollOffset(totalRows: totalRows, rowCount: rowCount))
  }

  /// The footer's note of which trains are showing, such as "SHOWING 9-16 OF 20", or `nil`
  /// when every train fits. It uses an ASCII hyphen, since the fonts load only ASCII glyphs.
  static func scrollSummary(offset: Int, totalRows: Int, rowCount: Int) -> String? {
    guard rowCount > 0, totalRows > rowCount else { return nil }
    let first = clampScrollOffset(offset, totalRows: totalRows, rowCount: rowCount) + 1
    let last = min(first - 1 + rowCount, totalRows)
    return "SHOWING \(first)-\(last) OF \(totalRows)"
  }

  func draw(at time: Double) {
    view.draw(at: .zero) { name, bounds in
      if let column = BoardColumn(rawValue: name) {
        drawColumn(column, in: bounds, at: time)
      } else if name == "rows" {
        drawRowDividers(in: bounds)
      }
    }
    windowManager.draw()
    windowManager.drawTooltip()
  }

  private func handleInput(maxOffset: Int) {
    guard !picker.isOpen(in: windowManager) else {
      if let choice = picker.update(in: windowManager) {
        scrollOffset = 0
        model.selectStation(code: choice.code, named: choice.name.uppercased())
      }
      return
    }

    if IsKeyPressed(.escape) {
      shouldQuit = true
    }
    if IsMouseButtonPressed(.left),
      let stationButton = view.bounds(named: "stationButton", at: .zero),
      CheckCollisionPointRec(GetMousePosition(), stationButton)
    {
      picker.open(in: windowManager)
      return
    }

    let wheel = GetMouseWheelMove()
    if wheel > 0 {
      scrollOffset = max(0, scrollOffset - 1)
    } else if wheel < 0 {
      scrollOffset = min(maxOffset, scrollOffset + 1)
    }

    if IsKeyPressed(.down) {
      scrollOffset = min(maxOffset, scrollOffset + 1)
    } else if IsKeyPressed(.up) {
      scrollOffset = max(0, scrollOffset - 1)
    } else if IsKeyPressed(.pageDown) {
      scrollOffset = min(maxOffset, scrollOffset + rowCount)
    } else if IsKeyPressed(.pageUp) {
      scrollOffset = max(0, scrollOffset - rowCount)
    } else if IsKeyPressed(.home) {
      scrollOffset = 0
    } else if IsKeyPressed(.end) {
      scrollOffset = maxOffset
    }
  }

  private func showModel(now: Date, hasRows: Bool, totalRows: Int) {
    view.setText(model.stationName, named: "stationName")
    view.setText(
      "STATION \(model.stationCode)  /  LIVE TRAIN INFORMATION",
      named: "stationDetail"
    )
    view.setText(model.stationTime(now: now), named: "clock")

    var summary = model.updateSummary
    if let shown = Self.scrollSummary(offset: scrollOffset, totalRows: totalRows, rowCount: rowCount) {
      summary += "  /  \(shown)"
    }
    view.setText(summary, named: "updateSummary")

    view.setText("VERSION \(AmtrakStatusApp.configuration.version)", named: "version")
    view.setText(model.emptyMessage, named: "statusMessage")
    view.setHidden(hasRows, named: "statusMessage")

    if shownStationName != model.stationName {
      shownStationName = model.stationName
      scrollOffset = 0
      SetWindowTitle("Amtrak Status - \(model.stationName)")
    }
  }

  private func showRows(_ rows: [TrainStatusRow], at time: Double, now: Date) {
    let visibleRows = Array(rows.dropFirst(scrollOffset).prefix(rowCount))
    let columns = BoardColumn.allCases
    let rowText = BoardRowText(timeZone: model.timeZone, now: now, dates: dates)
    let text = (0..<rowCount).map { index in
      columns.map { column in
        index < visibleRows.count ? rowText.value(of: column, in: visibleRows[index]) : column.placeholder
      }
    }
    let capacities = zip(columns, renderers).map { column, renderer in
      renderer.metrics.capacity(
        forWidth: Int(view.bounds(named: column.rawValue, at: .zero)?.width ?? 0)
      )
    }
    board.show(text, capacities: capacities, at: time)
  }

  private func drawColumn(_ column: BoardColumn, in bounds: Rectangle, at time: Double) {
    guard let columnIndex = BoardColumn.allCases.firstIndex(of: column) else { return }
    let renderer = renderers[columnIndex]
    let metrics = renderer.metrics
    let capacity = metrics.capacity(forWidth: Int(bounds.width))

    for row in 0..<rowCount {
      for index in 0..<capacity {
        renderer.draw(
          board.tile(row: row, column: columnIndex, index: index),
          x: Int(bounds.x) + index * (metrics.tileWidth + SplitFlapMetrics.tileGap),
          y: Int(bounds.y) + row * SplitFlapMetrics.rowHeight,
          height: Int(bounds.height),
          at: time
        )
      }
    }
  }

  private func drawRowDividers(in bounds: Rectangle) {
    let left = Int(bounds.x)
    let right = left + Int(bounds.width)
    for row in 0..<rowCount {
      let y = Int(bounds.y) + (row + 1) * SplitFlapMetrics.rowHeight - 3
      DrawLine(left, y, right, y, rowDivider)
    }
  }
}
