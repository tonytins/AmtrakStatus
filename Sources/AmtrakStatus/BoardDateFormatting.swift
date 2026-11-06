import Foundation

/// Reads Amtraker's timestamps and writes times the board's font can draw.
///
/// The formatters are not safe to share between threads, so each thread makes its own.
struct BoardDateFormatting {
  private let isoFormatter = ISO8601DateFormatter()

  // A fixed 24-hour format, such as "09:07". Every time is five characters, so colons line up
  // on the board, and it doesn't follow the system's style, which can use characters raylib's
  // default font cannot draw.
  private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm"
    return formatter
  }()

  private let weekdayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE"
    return formatter
  }()

  func parsedDate(from isoString: String?) -> Date? {
    guard let isoString, !isoString.isEmpty else { return nil }
    return isoFormatter.date(from: isoString)
  }

  func time(of date: Date, in zone: TimeZone?) -> String {
    timeFormatter.timeZone = zone ?? .current
    return timeFormatter.string(from: date)
  }

  /// Returns the short weekday name, such as "Tue".
  func weekday(of date: Date, in zone: TimeZone?) -> String {
    weekdayFormatter.timeZone = zone ?? .current
    return weekdayFormatter.string(from: date)
  }

  func punctuality(actual: String?, scheduled: String?) -> LateTrain {
    guard
      let actualDate = parsedDate(from: actual),
      let scheduledDate = parsedDate(from: scheduled)
    else {
      return .unknown
    }

    let differenceInMinutes = Int(actualDate.timeIntervalSince(scheduledDate) / 60)

    switch differenceInMinutes {
    case -1...1:
      return .onTime
    case ..<0:
      return .early(minutes: -differenceInMinutes)
    default:
      return .late(minutes: differenceInMinutes)
    }
  }
}
