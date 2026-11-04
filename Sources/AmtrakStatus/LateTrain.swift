enum LateTrain: Equatable, Sendable {
  case onTime
  case early(minutes: Int)
  case late(minutes: Int)
  case unknown
}
