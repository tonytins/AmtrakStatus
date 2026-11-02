import Foundation
import Hudini
import Raylib

struct StationChoice {
  let name: String
  let code: String
}

@MainActor
final class StationPicker {
  private let frame: WindowFrame
  private let codeField: TextField
  private let form: FormLayout
  private let theme: InterfaceTheme
  private var bounds = Rectangle()
  private var isFocused = false

  private let firstRow = [
    StationChoice(name: "Ashland, VA", code: "ASD"),
    StationChoice(name: "San Juan Capistrano, CA", code: "SNC"),
    StationChoice(name: "Fort Madison", code: "FMD"),
  ]
  private let secondRow = [
    StationChoice(name: "La Plata, MO", code: "LAP"),
    StationChoice(name: "Quincy, IL", code: "QCY"),
    StationChoice(name: "Spartanburg, SC", code: "SPB"),
  ]

  private(set) var isOpen = false

  init() {
    theme = InterfaceTheme(
      accent: Color(r: 238, g: 177, b: 72, a: 255),
      panel: Color(r: 17, g: 20, b: 23, a: 255),
      border: Color(r: 76, g: 68, b: 58, a: 255),
      text: .white,
      secondaryText: Color(r: 164, g: 155, b: 139, a: 255),
      titleBar: Color(r: 35, g: 31, b: 26, a: 255),
      selectedItem: Color(r: 49, g: 46, b: 41, a: 255)
    )
    frame = WindowFrame(title: "Change station", theme: theme)
    codeField = TextField(
      maximumLength: 5,
      accepting: Self.acceptsStationCodeCharacter,
      theme: theme
    )
    form = FormLayout(
      fields: [
        .init(label: "Station code:", control: codeField)
      ],
      footerHeight: Float(ButtonRow.rowHeight + 20)
    )
  }

  func open() {
    codeField.text = ""
    isFocused = true
    isOpen = true
  }

  func update() -> StationChoice? {
    guard isOpen else {
      while GetCharPressed() != 0 {}
      return nil
    }
    updateBounds()

    let mouse = GetMousePosition()
    _ = frame.followPointer(in: bounds)
    if case .close = frame.update(in: bounds) {
      isOpen = false
      return nil
    }

    if IsKeyPressed(.escape) {
      isOpen = false
      return nil
    }

    if IsMouseButtonPressed(.left) {
      if CheckCollisionPointRec(mouse, codeField.bounds) {
        isFocused = true
      } else if let choice = clickedPreset(at: mouse) {
        isOpen = false
        return choice
      } else if let button = clickedAction(at: mouse) {
        switch button {
        case 0:
          isOpen = false
          return nil
        case 1:
          return selectedCode()
        default:
          break
        }
      } else {
        isFocused = false
      }
    }

    if isFocused {
      _ = codeField.update()
      if IsKeyPressed(.enter) {
        return selectedCode()
      }
    } else {
      while GetCharPressed() != 0 {}
    }

    return nil
  }

  func draw() {
    guard isOpen else { return }
    updateBounds()

    DrawRectangle(
      0,
      0,
      Int(GetScreenWidth()),
      Int(GetScreenHeight()),
      theme.overlay
    )

    frame.draw(in: bounds)
    form.drawLabels(theme: theme)
    codeField.draw(isFocused: isFocused)

    let mouse = GetMousePosition()
    ButtonRow.draw(
      labels: firstRow.map(\.name),
      endingAt: firstRowCorner,
      mousePosition: mouse,
      theme: theme
    )
    ButtonRow.draw(
      labels: secondRow.map(\.name),
      endingAt: secondRowCorner,
      mousePosition: mouse,
      theme: theme
    )
    ButtonRow.draw(
      labels: ["Cancel", "Use code"],
      endingAt: form.buttonRowCorner,
      mousePosition: mouse,
      theme: theme
    )
  }

  private var firstRowCorner: Vector2 {
    Vector2(
      x: bounds.x + bounds.width - 18,
      y: codeField.bounds.y + codeField.bounds.height + 42
    )
  }

  private var secondRowCorner: Vector2 {
    Vector2(
      x: bounds.x + bounds.width - 18,
      y: firstRowCorner.y + Float(ButtonRow.rowHeight + 8)
    )
  }

  private func updateBounds() {
    let width: Float = 760
    let height: Float = 320
    bounds = frame.place(
      size: Vector2(x: width, y: height),
      at: Vector2(
        x: max(12, (Float(GetScreenWidth()) - width) / 2),
        y: max(12, (Float(GetScreenHeight()) - height) / 2)
      )
    )
    form.layout(in: WindowFrame.content(in: bounds))
  }

  private func clickedPreset(at point: Vector2) -> StationChoice? {
    if let index = ButtonRow.buttonIndex(
      at: point,
      endingAt: firstRowCorner,
      labels: firstRow.map(\.name)
    ) {
      return firstRow[index]
    }
    if let index = ButtonRow.buttonIndex(
      at: point,
      endingAt: secondRowCorner,
      labels: secondRow.map(\.name)
    ) {
      return secondRow[index]
    }
    return nil
  }

  private func clickedAction(at point: Vector2) -> Int? {
    ButtonRow.buttonIndex(
      at: point,
      endingAt: form.buttonRowCorner,
      labels: ["Cancel", "Use code"]
    )
  }

  private func selectedCode() -> StationChoice? {
    let code = codeField.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !code.isEmpty else { return nil }
    isOpen = false
    let preset = (firstRow + secondRow).first { $0.code == code }
    return preset ?? StationChoice(name: "STATION \(code)", code: code)
  }

  private static func acceptsStationCodeCharacter(_ character: Character) -> Bool {
    guard let scalar = character.unicodeScalars.first, scalar.isASCII else { return false }
    return CharacterSet.alphanumerics.contains(scalar)
  }
}
