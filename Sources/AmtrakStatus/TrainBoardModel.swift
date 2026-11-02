import AmtrakClient
import Foundation
import Logging

@MainActor
final class TrainBoardModel {
  private let logger = Logger(label: "com.tonybark.AmtrakStatus")
  private(set) var stationCode = "ASD"
  private(set) var stationName = "ASHLAND, VA"
  private let client = AmtrakClient()
  private let dates = AmtrakDateFormatting()
  private let staleDataThreshold: TimeInterval = 60 * 60 * 48

  private var timeZone = TimeZone(identifier: "America/New_York")
  private var refreshGenerations: Set<Int> = []
  private var selectionGeneration = 0
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
    let requestedCode = stationCode
    let generation = selectionGeneration
    guard refreshGenerations.insert(generation).inserted else { return }
    logger.info("Starting train status refresh for station \(requestedCode)")
    statusMessage = lastUpdatedAt == nil ? "FETCHING TRAIN STATUS" : "UPDATING TRAIN STATUS"
    defer { refreshGenerations.remove(generation) }

    do {
      let lookup = try await client.trainStationLookup(stationCode: requestedCode)
      guard generation == selectionGeneration else { return }
      timeZone = lookup.timeZone ?? timeZone

      let staleData = try await client.fetchStaleStatus()
      let staleTimes = Dictionary(
        staleData.lastUpdatedArr.map { ($0.trainID, $0.timeSince) },
        uniquingKeysWith: { first, _ in first }
      )

      var updatedRows: [TrainStatusRow] = []
      for number in lookup.trainNumbers {
        let trains = try await client.fetchAllTrainStatus(num: number)
        guard generation == selectionGeneration else { return }
        for train in trains {
          guard let leg = train.stations?.first(where: { $0.code == requestedCode }),
            !isStale(leg),
            !isDataStale(train.trainID, staleTimes: staleTimes)
          else {
            continue
          }

          let scheduledArrival = dates.parsedDate(from: leg.schArr)
          updatedRows.append(
            TrainStatusRow(
              trainID: train.trainID,
              scheduledArrival: scheduledArrival,
              scheduledTime: dates.time(from: leg.schArr, in: timeZone) ?? "--",
              trainNum: train.trainNum,
              service: train.routeName,
              destination: train.destName,
              punctuality: dates.isOnTime(actual: leg.arr, scheduled: leg.schArr)
            )
          )
        }
      }

      guard generation == selectionGeneration else { return }
      rows = updatedRows.sorted(by: {
        ($0.scheduledArrival ?? .distantFuture) < ($1.scheduledArrival ?? .distantFuture)
      })
      lastUpdatedAt = Date()
      statusMessage =
        rows.isEmpty ? "NO ACTIVE TRAINS REPORTED" : "\(rows.count) TRAINS AT \(requestedCode)"
      logger.info("Train status refresh completed with \(rows.count) active rows")
    } catch let AmtrakError.stationNotFound(code) {
      guard generation == selectionGeneration else { return }
      rows = []
      statusMessage = "STATION \(code) NOT FOUND"
      logger.error("Station \(code) was not found")
    } catch let AmtrakError.httpStatus(code) {
      guard generation == selectionGeneration else { return }
      statusMessage = "AMTRAKER RETURNED HTTP \(code)"
      logger.error("Amtraker returned HTTP status \(code)")
    } catch let AmtrakError.invalidURL(url) {
      guard generation == selectionGeneration else { return }
      statusMessage = "INVALID API URL: \(url)"
      logger.error("Invalid Amtraker API URL: \(url)")
    } catch AmtrakError.invalidResponse {
      guard generation == selectionGeneration else { return }
      statusMessage = "AMTRAKER RETURNED AN INVALID RESPONSE"
      logger.error("Amtraker returned a non-HTTP response")
    } catch {
      guard generation == selectionGeneration else { return }
      statusMessage = "UPDATE FAILED: \(error.localizedDescription)"
      logger.error("Train status refresh failed: \(error.localizedDescription)")
    }
  }

  func selectStation(code: String, named name: String) async {
    let code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !code.isEmpty else { return }

    selectionGeneration += 1
    stationCode = code
    stationName = name
    rows = []
    timeZone = nil
    lastUpdatedAt = nil
    statusMessage = "FETCHING TRAIN STATUS"
    await refresh()
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
