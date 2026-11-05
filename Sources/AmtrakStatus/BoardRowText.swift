import Foundation

/// Writes rows as the text each board column shows, for the board and for `--print`.
struct BoardRowText {
  /// The station's time zone, or `nil` to use this computer's.
  let timeZone: TimeZone?
  let dates: BoardDateFormatting

  func value(of column: BoardColumn, in row: TrainStatusRow) -> String {
    switch column {
    case .time: row.scheduledArrival.map { dates.boardTime(of: $0, in: timeZone) } ?? "--"
    case .number: row.trainNum
    case .train: row.service
    case .destination: row.destination
    case .early: row.earlyDelay
    case .late: row.lateDelay
    }
  }
}
