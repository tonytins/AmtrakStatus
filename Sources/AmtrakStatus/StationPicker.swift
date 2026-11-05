import Foundation
import Hudini
import Raylib

struct StationChoice: Equatable {
  let name: String
  let code: String

  private static let presetPrefix = "preset."
  private static let maximumCodeLength = 5

  /// The station the board opens on when none is given.
  static let ashland = StationChoice(name: "ASHLAND, VA", code: "ASD")

  init(name: String, code: String) {
    self.name = name
    self.code = code
  }

  /// Returns the choice for a control named `preset.<CODE>`, or `nil` for any other control.
  init?(presetControl control: String, name: String) {
    guard control.hasPrefix(Self.presetPrefix) else { return nil }
    self.name = name
    code = String(control.dropFirst(Self.presetPrefix.count))
  }

  /// Returns the choice for a typed code, or `nil` when it cannot be a station code.
  init?(typedCode text: String) {
    let code = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let isValid =
      !code.isEmpty
      && code.count <= Self.maximumCodeLength
      && code.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
    guard isValid else { return nil }
    self.code = code
    name = "STATION \(code)"
  }
}

/// The modal window that changes the station, laid out by `station-picker.xml`.
final class StationPicker {
  /// The controls the picker depends on.
  static let requiredControls = ["windowTitle", "stationCode", "problem", "cancel", "useCode"]

  private static let codeField = "stationCode"
  private static let screenMargin: Float = 12

  private let script: UIScript
  private let view: UIScriptView
  private let frame: WindowFrame
  private let overlay: Color
  private let size: Vector2

  private(set) var isOpen = false

  /// Creates the picker. Call this after `InitWindow`.
  init(script: UIScript) {
    self.script = script
    let frameStyle = script.styles["frame"]
    let standard = InterfaceTheme.standard
    let theme = InterfaceTheme(
      accent: frameStyle?.fillColor ?? standard.accent,
      panel: frameStyle?.backgroundColor ?? standard.panel,
      border: frameStyle?.borderColor ?? standard.border,
      text: frameStyle?.textColor ?? standard.text,
      secondaryText: frameStyle?.disabledTextColor ?? standard.secondaryText,
      titleBar: script.styles["frameTitle"]?.backgroundColor ?? standard.titleBar
    )
    view = UIScriptView(script: script, theme: theme)
    frame = WindowFrame(title: view.text(named: "windowTitle") ?? "", theme: theme)
    view.setHidden(true, named: "windowTitle")
    overlay = script.styles["frameOverlay"]?.backgroundColor ?? standard.overlay
    size = Vector2(
      x: script.window.size.width,
      y: script.window.size.height + Float(WindowFrame.titleHeight)
    )
  }

  func open() {
    view.setText("", named: Self.codeField)
    view.setText("", named: "problem")
    isOpen = true
  }

  /// Handles this frame's input, and returns the station once the user chooses one.
  func update() -> StationChoice? {
    guard isOpen else { return nil }

    let bounds = bounds
    _ = frame.followPointer(in: bounds)
    if frame.update(in: bounds) == .close || IsKeyPressed(.escape) {
      close()
      return nil
    }

    for event in view.update(at: contentOrigin(in: bounds)) {
      switch event {
      case .pressed("cancel"):
        close()
        return nil
      case .pressed("useCode"):
        guard case .submitted(let text)? = view.textField(named: Self.codeField)?.submit() else {
          continue
        }
        if let choice = choose(typedCode: text) { return choice }
      case .pressed(let control):
        guard let choice = StationChoice(
          presetControl: control,
          name: view.text(named: control) ?? control
        ) else { continue }
        close()
        return choice
      case .submitted(Self.codeField, let text):
        if let choice = choose(typedCode: text) { return choice }
      case .submitted, .changed:
        continue
      }
    }
    return nil
  }

  func draw() {
    guard isOpen else { return }
    let bounds = bounds
    DrawRectangle(0, 0, Int(GetScreenWidth()), Int(GetScreenHeight()), overlay)
    frame.draw(in: bounds)
    view.draw(at: contentOrigin(in: bounds))
  }

  private var bounds: Rectangle {
    frame.place(
      size: size,
      at: Vector2(
        x: max(Self.screenMargin, (Float(GetScreenWidth()) - size.x) / 2),
        y: max(Self.screenMargin, (Float(GetScreenHeight()) - size.y) / 2)
      )
    )
  }

  private func contentOrigin(in bounds: Rectangle) -> Vector2 {
    let content = WindowFrame.content(in: bounds)
    return Vector2(x: content.x, y: content.y)
  }

  private func choose(typedCode text: String) -> StationChoice? {
    guard let choice = StationChoice(typedCode: text) else {
      view.setText("STATION CODES USE LETTERS AND NUMBERS ONLY", named: "problem")
      return nil
    }
    close()
    return choice
  }

  private func close() {
    view.clearFocus()
    isOpen = false
  }
}
