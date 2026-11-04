import Foundation

/// Reads Amtraker's timestamps and writes times the board's font can draw.
///
/// The formatters are not safe to share between threads, so each thread makes its own.
struct BoardDateFormatting {
  private let isoFormatter = ISO8601DateFormatter()

  // A fixed format, because the system's short time style puts a narrow no-break space
  // before AM or PM on current systems, and raylib's default font cannot draw it.
  private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "h:mm a"
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

  /// Returns a time padded so its colon stays in the same tile for one- and two-digit hours.
  func boardTime(from isoString: String?, in zone: TimeZone?) -> String? {
    guard let date = parsedDate(from: isoString) else { return nil }
    let time = time(of: date, in: zone)
    return time.count < 8 ? " " + time : time
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
