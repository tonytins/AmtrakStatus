import Foundation

@MainActor
struct AmtrakDateFormatting {
  let isoFormatter = ISO8601DateFormatter()

  let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
  }()

  let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()

  func parsedDate(from isoString: String?) -> Date? {
    guard let isoString, !isoString.isEmpty else { return nil }
    return isoFormatter.date(from: isoString)
  }

  func time(from isoString: String?, in zone: TimeZone?, comparedTo originZone: TimeZone? = nil)
    -> String?
  {
    guard let isoString, !isoString.isEmpty,
      let date = isoFormatter.date(
        from: isoString)
    else {
      return nil
    }

    timeFormatter.timeZone = zone

    let formatted = timeFormatter.string(from: date)

    guard
      let zone,
      let originZone,
      zone.identifier != originZone.identifier,
      let abbreviation = zone.abbreviation(for: date)
    else {
      return formatted
    }

    return "\(formatted) \(abbreviation)"
  }

  func isOnTime(actual: String?, scheduled: String?) -> LateTrain {

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

  func localTime(timeZone: TimeZone?) -> String {
    let now = Date()
    timeFormatter.timeZone = timeZone
    return timeFormatter.string(from: now)
  }

  func date(from isoString: String?) -> String? {
    guard let isoString, !isoString.isEmpty,
      let date = isoFormatter.date(
        from: isoString)
    else {
      return nil
    }

    return dateFormatter.string(from: date)
  }
}
