import Foundation
import Logging
import Raylib

/// The fonts in the `Interface` folder.
///
/// They are named here rather than in the interface documents, because UIScript has no way to
/// name a font yet. Move them into the documents once Hudini can.
enum InterfaceFont: String, CaseIterable {
  /// The split-flap tiles.
  case board = "B612Mono-Bold"
  /// Everything else: the header, headings, footer, and the station picker.
  case text = "Overpass-Regular"

  private static let logger = Logger(label: "com.tonybark.AmtrakStatus")

  /// The size each font's glyphs are drawn at when loaded. Text from 10 to 34 pixels is scaled
  /// down from this with filtering, which keeps small sizes smoother than scaling up would.
  private static let loadedSize = 48

  /// Where the font file is, or `nil` when it is missing.
  var location: URL? {
    InterfaceDocument.location(named: rawValue, withExtension: "ttf")
  }

  /// Loads the font. Call it after `InitWindow`, and unload it with `UnloadFont` before
  /// `CloseWindow`. Returns `nil`, with a warning, when the file is missing or can't be read,
  /// so text falls back to raylib's own font rather than the app failing to start.
  func load() -> Font? {
    guard let location else {
      Self.logger.warning("The font \(rawValue).ttf is missing, so raylib's font is used instead")
      return nil
    }
    // The C function, since the Int overload has no way to pass "all of ASCII" (nil).
    let font = LoadFontEx(location.path, Int32(Self.loadedSize), nil, 0)
    guard IsFontValid(font) else {
      Self.logger.warning("The font \(location.path) couldn't be read, so raylib's font is used")
      return nil
    }
    SetTextureFilter(font.texture, .bilinear)
    Self.logger.info("Loaded the font \(location.path)")
    return font
  }
}
