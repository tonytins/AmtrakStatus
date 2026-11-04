import Foundation

public struct TrainAlert: Codable, Sendable {
  public var message: String
}

public struct Station: Codable, Sendable {
  public var name: String
  public var code: String
  public var tz: String
  public var bus: Bool
  public var schArr: String
  public var schDep: String
  /// The actual or estimated arrival time. Amtraker reports `null` when it has neither.
  public var arr: String?
  /// The actual or estimated departure time. Amtraker reports `null` when it has neither.
  public var dep: String?
  public var arrCmnt: String
  public var depCmnt: String
  public var status: StationStatus
  public var stopIconColor: String
  public var platform: String
}

public enum StationStatus: String, Codable, Sendable {
  case enroute = "Enroute"
  case station = "Station"
  case departed = "Departed"
  case unknown = "Unknown"

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    self = StationStatus(rawValue: rawValue) ?? .unknown
  }
}

public struct Train: Codable, Sendable {
  public var routeName: String
  public var trainNum: String
  public var trainNumRaw: String?
  public var trainID: String
  public var lat: Double?
  public var lon: Double?
  public var trainTimely: String?
  public var iconColor: String?
  public var textColor: String?
  public var heading: String?
  public var eventCode: String?
  public var eventTZ: String?
  public var eventName: String?
  public var origCode: String?
  public var origName: String
  public var destCode: String?
  public var destName: String
  public var trainState: String?
  public var velocity: Double?
  public var statusMsg: String?
  public var createdAt: String?
  public var updatedAt: String?
  public var lastValTS: String?
  public var objectID: Int?
  public var provider: String?
  public var providerShort: String?
  public var onlyOfTrainNum: Bool?
  public var alerts: [TrainAlert]?
  public var stations: [Station]?
}

public struct StationMeta: Codable, Sendable {
  public var name: String
  public var code: String
  public var tz: String?
  public var lat: Double?
  public var lon: Double?
  public var hasAddress: Bool?
  public var address1: String?
  public var address2: String?
  public var city: String?
  public var state: String?
  public var zip: String?
  public var trains: [String]
}

public struct StaleData: Codable, Sendable {
  public var activeTrains: Int
  public var avgLastUpdate: Double
  public var lastUpdatedArr: [TrainFreshness]
  public var medianLastUpdate: Double
}

public struct TrainFreshness: Codable, Sendable {
  public var trainID: String
  public var timeSince: Double
}

public typealias TrainResponse = [String: [Train]]
public typealias StationResponse = [String: StationMeta]
