import Hudini
import Raylib

/// Draws split-flap tiles in the colors and font size of a `UIScript` style.
struct SplitFlapRenderer {
  private static let defaultFontSize = 20
  private static let defaultGlyph = Color.white
  private static let defaultTile = Color(r: 30, g: 32, b: 38, a: 255)

  let metrics: SplitFlapMetrics
  private let glyphColor: Color
  private let tileColor: Color
  private let flapColor: Color
  private let hingeColor: Color

  init(style: UIScript.Style?) {
    metrics = SplitFlapMetrics(fontSize: style?.fontSize ?? Self.defaultFontSize)
    glyphColor = style?.textColor ?? Self.defaultGlyph
    tileColor = style?.backgroundColor ?? Self.defaultTile
    flapColor = style?.fillColor ?? tileColor
    hingeColor = style?.borderColor ?? tileColor
  }

  /// Draws a tile at (`x`, `y`) with the given height.
  ///
  /// While flipping, the new character shows in the upper half and the old one in the lower
  /// half. A flap covers the upper half and folds down to the hinge, then a flap carrying the
  /// new character unfolds over the lower half. The last flap frame matches the settled tile.
  func draw(_ tile: FlapTile, x: Int, y: Int, height: Int, at time: Double) {
    let width = metrics.tileWidth
    let upperHeight = height / 2
    let lowerHeight = height - upperHeight
    let hinge = y + upperHeight
    let progress = tile.progress(at: time)

    DrawRectangle(x, y, width, height, tileColor)

    if progress <= 0 || progress >= 1 {
      drawGlyph(progress >= 1 ? tile.target : tile.current, x: x, y: y, height: height)
    } else {
      drawGlyph(tile.target, x: x, y: y, height: height, clipY: y, clipHeight: upperHeight)
      drawGlyph(tile.current, x: x, y: y, height: height, clipY: hinge, clipHeight: lowerHeight)

      if progress < 0.5 {
        let flapHeight = Int((1 - progress * 2) * Double(upperHeight))
        let flapY = hinge - flapHeight
        DrawRectangle(x, flapY, width, flapHeight, flapColor)
        drawGlyph(tile.current, x: x, y: y, height: height, clipY: flapY, clipHeight: flapHeight)
      } else {
        let flapHeight = Int((progress * 2 - 1) * Double(lowerHeight))
        DrawRectangle(x, hinge, width, flapHeight, flapColor)
        drawGlyph(tile.target, x: x, y: y, height: height, clipY: hinge, clipHeight: flapHeight)
      }
    }

    DrawLine(x, hinge, x + width, hinge, hingeColor)
  }

  private func drawGlyph(
    _ character: Character,
    x: Int,
    y: Int,
    height: Int,
    clipY: Int,
    clipHeight: Int
  ) {
    guard clipHeight > 0 else { return }
    BeginScissorMode(x, clipY, metrics.tileWidth, clipHeight)
    defer { EndScissorMode() }
    drawGlyph(character, x: x, y: y, height: height)
  }

  private func drawGlyph(_ character: Character, x: Int, y: Int, height: Int) {
    guard character != " " else { return }
    let glyph = String(character)
    let fontSize = min(metrics.fontSize, max(8, height - 6))
    DrawText(
      glyph,
      x + (metrics.tileWidth - MeasureText(glyph, fontSize)) / 2,
      y + (height - fontSize) / 2,
      fontSize,
      glyphColor
    )
  }
}
