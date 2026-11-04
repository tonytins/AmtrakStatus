import Foundation

struct TrainStatusRow: Identifiable, Equatable, Sendable {
  var id: String { trainID }

  var trainID: String
  var scheduledArrival: Date?
  var scheduledTime: String
  var trainNum: String
  var service: String
  var destination: String
  var punctuality: LateTrain

  var earlyDelay: String {
    guard case .early(let minutes) = punctuality else { return "" }
    return "\(minutes)M"
  }

  var lateDelay: String {
    guard case .late(let minutes) = punctuality else { return "" }
    return "\(minutes)M"
  }
}

/// The columns of the board. Each raw value names the region that places its tiles in `board.xml`.
enum BoardColumn: String, CaseIterable {
  case time = "columnTime"
  case number = "columnNumber"
  case train = "columnTrain"
  case destination = "columnDestination"
  case early = "columnEarly"
  case late = "columnLate"

  /// What the column shows in a row with no train.
  var placeholder: String {
    self == .time ? "  :" : ""
  }

  func value(in row: TrainStatusRow) -> String {
    switch self {
    case .time: row.scheduledTime
    case .number: row.trainNum
    case .train: row.service
    case .destination: row.destination
    case .early: row.earlyDelay
    case .late: row.lateDelay
    }
  }
}
