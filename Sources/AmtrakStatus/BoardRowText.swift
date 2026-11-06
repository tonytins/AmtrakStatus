import Foundation

/// Writes rows as the text each board column shows, for the board and for `--print`.
///
/// Make one for each frame or print, since a row's text depends on the current time.
struct BoardRowText {
  /// The station's time zone, or `nil` to use this computer's.
  let timeZone: TimeZone?
  let dates: BoardDateFormatting
  private let now: Date
  private let calendar: Calendar

  init(timeZone: TimeZone?, now: Date, dates: BoardDateFormatting) {
    self.timeZone = timeZone
    self.now = now
    self.dates = dates
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone ?? .current
    self.calendar = calendar
  }

  func value(of column: BoardColumn, in row: TrainStatusRow) -> String {
    switch column {
    case .time: row.scheduledArrival.map(time(of:)) ?? "--"
    case .number: row.trainNum
    case .train: row.service
    case .destination: row.destination
    case .early: row.earlyDelay
    case .late: row.lateDelay
    }
  }

  /// Returns the 24-hour time, followed by the weekday when it is not today at the station,
  /// such as "09:07 FRI". Today's times have nothing after them.
  private func time(of date: Date) -> String {
    let time = dates.time(of: date, in: timeZone)
    guard !calendar.isDate(date, inSameDayAs: now) else { return time }
    return "\(time) \(dates.weekday(of: date, in: timeZone).uppercased())"
  }
}
