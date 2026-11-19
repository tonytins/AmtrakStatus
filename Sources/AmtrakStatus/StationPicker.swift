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

/// The modal window that changes the station, laid out by `station-picker.uix`.
final class StationPicker {
  /// The controls the picker depends on.
  static let requiredControls = ["windowTitle", "stationCode", "problem", "cancel", "useCode"]

  private static let codeField = "stationCode"
  private static let screenMargin: Float = 12

  private let script: UIScript
  private let view: UIScriptView
  private let frame: WindowFrame
  private let theme: InterfaceTheme

  /// Creates the picker, drawing its text in `font`, or raylib's font when it is `nil`. Call
  /// this after `InitWindow`.
  init(script: UIScript, font: Font?) {
    self.script = script
    let frameStyle = script.styles["frame"]
    let standard = InterfaceTheme.standard
    let theme = InterfaceTheme(
      accent: frameStyle?.fillColor ?? standard.accent,
      overlay: script.styles["frameOverlay"]?.backgroundColor ?? standard.overlay,
      panel: frameStyle?.backgroundColor ?? standard.panel,
      border: frameStyle?.borderColor ?? standard.border,
      text: frameStyle?.textColor ?? standard.text,
      secondaryText: frameStyle?.disabledTextColor ?? standard.secondaryText,
      titleBar: script.styles["frameTitle"]?.backgroundColor ?? standard.titleBar,
      font: font
    )
    self.theme = theme
    view = UIScriptView(script: script, theme: theme)
    frame = WindowFrame(view: view, title: view.text(named: "windowTitle") ?? "Change station")
    view.setHidden(true, named: "windowTitle")
  }

  /// Whether the picker window is open in `manager`.
  func isOpen(in manager: WindowManager) -> Bool {
    manager.isOpen(frame)
  }

  /// Opens the picker centered on the screen as a modal window.
  func open(in manager: WindowManager) {
    view.setText("", named: Self.codeField)
    view.setText("", named: "problem")
    view.textField(named: Self.codeField)?.setFocused(true)
    let screenWidth = Float(GetScreenWidth())
    let screenHeight = Float(GetScreenHeight())
    let windowBounds = frame.place(at: .zero)
    let centered = Vector2(
      x: max(Self.screenMargin, (screenWidth - windowBounds.width) / 2),
      y: max(Self.screenMargin, (screenHeight - windowBounds.height) / 2)
    )
    manager.open(frame, at: centered, modal: true, dimsBehind: true)
  }

  /// Closes the picker window.
  func close(in manager: WindowManager) {
    view.clearFocus()
    manager.close(frame)
  }

  /// Handles this frame's input, and returns the station once the user chooses one.
  func update(in manager: WindowManager) -> StationChoice? {
    guard manager.isOpen(frame) else { return nil }

    if IsKeyPressed(.escape) {
      close(in: manager)
      return nil
    }

    let events = manager.update()
    for event in events where event.window === frame {
      switch event.event {
      case .closeRequested:
        close(in: manager)
        return nil
      case .minimizeRequested:
        break
      case .view(.pressed("cancel")):
        close(in: manager)
        return nil
      case .view(.pressed("useCode")):
        guard case .submitted(let text)? = view.textField(named: Self.codeField)?.submit() else {
          continue
        }
        if let choice = choose(typedCode: text, in: manager) { return choice }
      case .view(.pressed(let control)):
        guard
          let choice = StationChoice(
            presetControl: control,
            name: view.text(named: control) ?? control
          )
        else { continue }
        close(in: manager)
        return choice
      case .view(.submitted(Self.codeField, let text)):
        if let choice = choose(typedCode: text, in: manager) { return choice }
      case .view:
        continue
      }
    }
    return nil
  }

  private func choose(typedCode text: String, in manager: WindowManager) -> StationChoice? {
    guard let choice = StationChoice(typedCode: text) else {
      view.setText("STATION CODES USE LETTERS AND NUMBERS ONLY", named: "problem")
      return nil
    }
    close(in: manager)
    return choice
  }
}
