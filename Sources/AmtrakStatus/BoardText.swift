import Foundation

/// The board as plain text for `--print`: a header line, then one line per row, with fields
/// separated by tabs so other programs can read it.
enum BoardText {
  static let header = ["time", "number", "train", "to", "early", "late"]

  static func lines(for rows: [TrainStatusRow]) -> [String] {
    let fields = rows.map {
      [$0.scheduledTime, $0.trainNum, $0.service, $0.destination, $0.earlyDelay, $0.lateDelay]
    }
    return ([header] + fields).map { line in
      // The board pads times to line up its tiles, which means nothing here.
      line.map { $0.replacing("\t", with: " ").trimmingCharacters(in: .whitespaces) }
        .joined(separator: "\t")
    }
  }
}
