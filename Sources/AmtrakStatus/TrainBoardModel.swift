import AmtrakClient
import Foundation
import Logging

@MainActor
final class TrainBoardModel {
  private let logger = Logger(label: "com.tonybark.AmtrakStatus")
  private let stationCode = "ASD"
  private let client = AmtrakClient()
  private let dates = AmtrakDateFormatting()
  private let staleDataThreshold: TimeInterval = 60 * 60 * 48

  private var timeZone = TimeZone(identifier: "America/New_York")
  private var isRefreshing = false
  private let clockFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter
  }()

  private(set) var rows: [TrainStatusRow] = []
  private(set) var statusMessage = "CONNECTING TO AMTRAKER"
  private(set) var lastUpdatedAt: Date?

  var localTime: String {
    clockFormatter.timeZone = timeZone
    return clockFormatter.string(from: Date())
  }

  var lastUpdatedTime: String? {
    guard let lastUpdatedAt else { return nil }
    clockFormatter.timeZone = timeZone
    return clockFormatter.string(from: lastUpdatedAt)
  }

  func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    logger.info("Starting train status refresh for station \(stationCode)")
    statusMessage = lastUpdatedAt == nil ? "FETCHING TRAIN STATUS" : "UPDATING TRAIN STATUS"
    defer { isRefreshing = false }

    do {
      let lookup = try await client.trainStationLookup(stationCode: stationCode)
      timeZone = lookup.timeZone ?? timeZone

      let staleData = try await client.fetchStaleStatus()
      let staleTimes = Dictionary(
        staleData.lastUpdatedArr.map { ($0.trainID, $0.timeSince) },
        uniquingKeysWith: { first, _ in first }
      )

      var updatedRows: [TrainStatusRow] = []
      for number in lookup.trainNumbers {
        let trains = try await client.fetchAllTrainStatus(num: number)
        for train in trains {
          guard let leg = train.stations?.first(where: { $0.code == stationCode }),
            !isStale(leg),
            !isDataStale(train.trainID, staleTimes: staleTimes)
          else {
            continue
          }

          let scheduledArrival = dates.parsedDate(from: leg.schArr)
          let arrivalTime =
            dates.time(from: leg.arr, in: timeZone)
            ?? dates.time(from: leg.schArr, in: timeZone)
            ?? "--"

          updatedRows.append(
            TrainStatusRow(
              trainID: train.trainID,
              scheduledArrival: scheduledArrival,
              arrivalTime: arrivalTime,
              trainNum: train.trainNum,
              service: train.routeName,
              origin: train.origName,
              destination: train.destName,
              presence: leg.status,
              punctuality: dates.isOnTime(actual: leg.arr, scheduled: leg.schArr),
              track: leg.platform
            )
          )
        }
      }

      rows = updatedRows.sorted(by: {
        ($0.scheduledArrival ?? .distantFuture) < ($1.scheduledArrival ?? .distantFuture)
      })
      lastUpdatedAt = Date()
      statusMessage = rows.isEmpty ? "NO ACTIVE TRAINS REPORTED" : "\(rows.count) TRAINS AT ASHLAND"
      logger.info("Train status refresh completed with \(rows.count) active rows")
    } catch let AmtrakError.stationNotFound(code) {
      rows = []
      statusMessage = "STATION \(code) NOT FOUND"
      logger.error("Station \(code) was not found")
    } catch let AmtrakError.httpStatus(code) {
      statusMessage = "AMTRAKER RETURNED HTTP \(code)"
      logger.error("Amtraker returned HTTP status \(code)")
    } catch let AmtrakError.invalidURL(url) {
      statusMessage = "INVALID API URL: \(url)"
      logger.error("Invalid Amtraker API URL: \(url)")
    } catch AmtrakError.invalidResponse {
      statusMessage = "AMTRAKER RETURNED AN INVALID RESPONSE"
      logger.error("Amtraker returned a non-HTTP response")
    } catch {
      statusMessage = "UPDATE FAILED: \(error.localizedDescription)"
      logger.error("Train status refresh failed: \(error.localizedDescription)")
    }
  }

  private func isStale(_ leg: Station) -> Bool {
    guard leg.status == .departed,
      let departureDate = dates.parsedDate(from: leg.dep)
        ?? dates.parsedDate(from: leg.schDep)
    else {
      return false
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone ?? .current
    return calendar.startOfDay(for: departureDate) < calendar.startOfDay(for: Date())
  }

  private func isDataStale(_ trainID: String, staleTimes: [String: TimeInterval]) -> Bool {
    guard let timeSince = staleTimes[trainID] else { return false }
    return timeSince > staleDataThreshold
  }
}
