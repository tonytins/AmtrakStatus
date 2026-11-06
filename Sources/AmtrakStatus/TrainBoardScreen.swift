import Foundation
import Hudini
import Raylib

/// Connects the model to `board.xml`: it fills the document's text controls, draws split-flap
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
  private let renderers: [SplitFlapRenderer]
  private let rowDivider: Color
  private let dates = BoardDateFormatting()
  private var board = SplitFlapBoard()
  private var rowCount = 1
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
    handleInput()
    model.update(now: now)
    view.setWindowSize(Vector2(x: Float(GetScreenWidth()), y: Float(GetScreenHeight())))
    let rows = model.shownRows(now: now)
    showModel(now: now, hasRows: !rows.isEmpty)
    showRows(rows, at: time, now: now)
  }

  func draw(at time: Double) {
    view.draw(at: .zero) { name, bounds in
      if let column = BoardColumn(rawValue: name) {
        drawColumn(column, in: bounds, at: time)
      } else if name == "rows" {
        drawRowDividers(in: bounds)
      }
    }
    picker.draw()
  }

  private func handleInput() {
    guard !picker.isOpen else {
      if let choice = picker.update() {
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
      picker.open()
    }
  }

  private func showModel(now: Date, hasRows: Bool) {
    view.setText(model.stationName, named: "stationName")
    view.setText(
      "STATION \(model.stationCode)  /  LIVE TRAIN INFORMATION",
      named: "stationDetail"
    )
    view.setText(model.stationTime(now: now), named: "clock")
    view.setText(model.updateSummary, named: "updateSummary")
    view.setText("VERSION \(AmtrakStatusApp.configuration.version)", named: "version")
    view.setText(model.emptyMessage, named: "statusMessage")
    view.setHidden(hasRows, named: "statusMessage")

    if shownStationName != model.stationName {
      shownStationName = model.stationName
      SetWindowTitle("Amtrak Status - \(model.stationName)")
    }
  }

  private func showRows(_ rows: [TrainStatusRow], at time: Double, now: Date) {
    let rowsHeight = view.bounds(named: "rows", at: .zero)?.height ?? 0
    rowCount = SplitFlapMetrics.rowCount(forHeight: Int(rowsHeight))

    let columns = BoardColumn.allCases
    let rowText = BoardRowText(timeZone: model.timeZone, now: now, dates: dates)
    let text = (0..<rowCount).map { index in
      columns.map { column in
        index < rows.count ? rowText.value(of: column, in: rows[index]) : column.placeholder
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
