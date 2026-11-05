import Foundation

/// The board as plain text for `--print`: a header line, then one line per row, with fields
/// separated by tabs so other programs can read it.
enum BoardText {
  static let header = ["time", "number", "train", "to", "early", "late"]

  /// Columns follow `BoardColumn`'s order, which `header` names.
  static func lines(for rows: [TrainStatusRow], timeZone: TimeZone?) -> [String] {
    let text = BoardRowText(timeZone: timeZone, dates: BoardDateFormatting())
    let fields = rows.map { row in BoardColumn.allCases.map { text.value(of: $0, in: row) } }
    return ([header] + fields).map { line in
      // The board pads times to line up its tiles, which means nothing here.
      line.map { $0.replacing("\t", with: " ").trimmingCharacters(in: .whitespaces) }
        .joined(separator: "\t")
    }
  }
}
