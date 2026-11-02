import Foundation

enum LateTrain {
  case onTime
  case early(minutes: Int)
  case late(minutes: Int)
  case unknown

  var description: String {
    switch self {
    case .onTime:
      return "On Time"
    case .early(let minutes):
      return "\(Self.formatted(minutes)) early"
    case .late(let minutes):
      return "\(Self.formatted(minutes)) late"
    case .unknown:
      return "Status unavailable"
    }
  }

  static func formatted(_ minutes: Int) -> String {
    let hours = minutes / 60
    let remainingMinutes = minutes % 60

    let hoursPart = "\(hours) \(hours.pluralized(singular: "hr", plural: "hrs"))"
    let minutesPart =
      "\(remainingMinutes) \(remainingMinutes.pluralized(singular: "min", plural: "mins"))"

    guard hours > 0 else {
      return "\(minutes) \(minutes.pluralized(singular: "min", plural: "mins"))"
    }

    guard remainingMinutes > 0 else { return hoursPart }
    return "\(hoursPart) \(minutesPart)"
  }
}
