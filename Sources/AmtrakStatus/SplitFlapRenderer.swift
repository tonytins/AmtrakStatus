import Hudini
import Raylib

/// Draws split-flap tiles in the colors and font size of a `UIScript` style.
struct SplitFlapRenderer {
  /// How round the tiles' corners are, in pixels. It lives here because UIScript can't set
  /// corners on a style yet; move it into `board.xml` once Hudini can.
  static let cornerRadius: Float = 3

  private static let defaultFontSize = 20
  private static let defaultGlyph = Color.white
  private static let defaultTile = Color(r: 30, g: 32, b: 38, a: 255)

  let metrics: SplitFlapMetrics
  // Draws the glyphs in the tiles' font and the tiles with rounded corners.
  private let theme: InterfaceTheme
  private let glyphColor: Color
  private let tileColor: Color
  private let flapColor: Color
  private let hingeColor: Color

  /// Creates a renderer for tiles in `style`, with glyphs in `font`, or raylib's font when it is
  /// `nil`.
  init(style: UIScript.Style?, font: Font?) {
    metrics = SplitFlapMetrics(fontSize: style?.fontSize ?? Self.defaultFontSize)
    theme = InterfaceTheme(font: font, cornerRadius: Self.cornerRadius)
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

    theme.fillRectangle(
      Rectangle(x: Float(x), y: Float(y), width: Float(width), height: Float(height)), tileColor)

    if progress <= 0 || progress >= 1 {
      drawGlyph(progress >= 1 ? tile.target : tile.current, x: x, y: y, height: height)
    } else {
      drawGlyph(tile.target, x: x, y: y, height: height, clipY: y, clipHeight: upperHeight)
      drawGlyph(tile.current, x: x, y: y, height: height, clipY: hinge, clipHeight: lowerHeight)

      if progress < 0.5 {
        let flapHeight = Int((1 - progress * 2) * Double(upperHeight))
        let flapY = hinge - flapHeight
        drawFlap(x: x, top: flapY, bottom: hinge, roundedEdgeAtTop: true)
        drawGlyph(tile.current, x: x, y: y, height: height, clipY: flapY, clipHeight: flapHeight)
      } else {
        let flapHeight = Int((progress * 2 - 1) * Double(lowerHeight))
        drawFlap(x: x, top: hinge, bottom: hinge + flapHeight, roundedEdgeAtTop: false)
        drawGlyph(tile.target, x: x, y: y, height: height, clipY: hinge, clipHeight: flapHeight)
      }
    }

    DrawLine(x, hinge, x + width, hinge, hingeColor)
  }

  /// Draws a flap from `top` to `bottom` with rounded corners on its outer edge only, as half a
  /// tile has: the edge at the hinge stays square. The flap is drawn as a rounded shape that
  /// runs past the hinge by a corner's height, and clipped at the hinge.
  private func drawFlap(x: Int, top: Int, bottom: Int, roundedEdgeAtTop: Bool) {
    let height = bottom - top
    guard height > 0 else { return }
    let overhang = Int(Self.cornerRadius.rounded(.up))
    let shape = Rectangle(
      x: Float(x),
      y: Float(roundedEdgeAtTop ? top : top - overhang),
      width: Float(metrics.tileWidth),
      height: Float(height + overhang)
    )
    BeginScissorMode(x, top, metrics.tileWidth, height)
    defer { EndScissorMode() }
    theme.fillRectangle(shape, flapColor)
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
    theme.drawText(
      glyph,
      x: x + (metrics.tileWidth - theme.textWidth(of: glyph, size: fontSize)) / 2,
      y: y + (height - fontSize) / 2,
      size: fontSize,
      color: glyphColor
    )
  }
}
