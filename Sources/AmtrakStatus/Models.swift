import Foundation
import AmtrakClient

struct TrainStatusRow: Identifiable {
  var id: String { trainID }

  var trainID: String
  var scheduledArrival: Date?
  var arrivalTime: String
  var trainNum: String
  var service: String
  var origin: String
  var destination: String
  var presence: StationStatus
  var punctuality: LateTrain
  var track: String
}
