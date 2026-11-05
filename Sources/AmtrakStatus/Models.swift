import Foundation

/// One train's stop at the station. It holds data rather than board text, because what a row
/// shows can depend on the time and on the other rows; `BoardRowText` writes it out.
struct TrainStatusRow: Identifiable, Equatable, Sendable {
  var id: String { trainID }

  var trainID: String
  var scheduledArrival: Date?
  /// Amtraker's estimate, or the actual arrival once the train has arrived.
  var estimatedArrival: Date?
  var trainNum: String
  /// The day of the month the train's run started, from its ID, such as 3 for `67-3`.
  var runDay: Int?
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
}
