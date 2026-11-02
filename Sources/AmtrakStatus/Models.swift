import Foundation
import AmtrakClient

struct TrainStatusRow: Identifiable {
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
