import Foundation
import Hudini
import Logging

/// A problem with a bundled interface document.
enum InterfaceDocumentError: LocalizedError, Equatable {
  case notFound(document: String)
  case missingControls(document: String, names: [String])
  case missingFont(name: String)

  var errorDescription: String? {
    switch self {
    case .notFound(let document):
      "The interface document \(document).xml is missing from the app's resources."
    case .missingControls(let document, let names):
      "\(document).xml has no control named \(names.joined(separator: ", "))."
    case .missingFont(let name):
      "The font \(name).ttf is missing from the app's resources."
    }
  }
}

/// Loads the UIScript documents in the `Interface` resource directory.
enum InterfaceDocument {
  private static let logger = Logger(label: "com.tonybark.AmtrakStatus")

  /// Finds a file in the `Interface` folder, such as a document or a font: in a package's
  /// `Interface` folder if it has one, and otherwise in the resource bundle SwiftPM builds for
  /// `swift run` and `swift test`.
  ///
  /// Packages don't carry that bundle: on macOS, `Bundle.module` looks for it in the root of the
  /// `.app`, where code signing doesn't allow it. `folder` defaults to the executable's folder,
  /// or `Contents/Resources` in a Mac app.
  static func location(
    named name: String,
    withExtension fileExtension: String = "xml",
    packagedIn folder: URL? = Bundle.main.resourceURL
  ) -> URL? {
    if let packaged = folder?.appendingPathComponent("Interface/\(name).\(fileExtension)"),
      FileManager.default.fileExists(atPath: packaged.path)
    {
      return packaged
    }
    return Bundle.module.url(
      forResource: name, withExtension: fileExtension, subdirectory: "Interface")
  }

  /// Loads a document and checks that it has every control the app depends on.
  ///
  /// Attributes the reader ignored are logged, because a misspelled one lands there.
  static func load(named name: String, requiring required: [String]) throws -> UIScript {
    guard let url = location(named: name) else {
      throw InterfaceDocumentError.notFound(document: name)
    }

    let script = try UIScript(contentsOf: url)
    for ignored in script.ignoredAttributes {
      logger.warning(
        "\(name).xml line \(ignored.line): \(ignored.element) ignores '\(ignored.attribute)'"
      )
    }

    let missing = required.filter { script.control(named: $0) == nil }
    guard missing.isEmpty else {
      throw InterfaceDocumentError.missingControls(document: name, names: missing)
    }
    return script
  }
}
