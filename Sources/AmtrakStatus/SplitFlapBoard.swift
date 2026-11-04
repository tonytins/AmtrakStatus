/// One character position on the board, flipping from `current` to `target`.
struct FlapTile: Equatable {
  var current: Character = " "
  var target: Character = " "
  var startsAt: Double = 0

  /// How far the flip has gone at `time`, from 0 before it starts to 1 once it ends.
  func progress(at time: Double) -> Double {
    guard current != target else { return 1 }
    return min(1, max(0, (time - startsAt) / SplitFlapBoard.flipDuration))
  }

  /// The character a reader sees at `time`.
  func character(at time: Double) -> Character {
    progress(at: time) >= 0.5 ? target : current
  }
}

/// Tracks the tiles of a board whose positions stay put while their text changes, so a new
/// train flips over whatever that row showed before.
struct SplitFlapBoard {
  static let flipDuration = 0.42

  private struct Position: Hashable {
    let row: Int
    let column: Int
    let index: Int
  }

  private var text: [[String]] = []
  private var capacities: [Int] = []
  private var tiles: [Position: FlapTile] = [:]

  /// Starts flipping any tile whose character differs from `text`, indexed by row and column.
  ///
  /// `capacities` gives each column's tile count, and longer text is cut to fit. This does
  /// nothing when the text and capacities are unchanged, so it is cheap to call every frame.
  /// Tiles that no longer fit are forgotten.
  mutating func show(_ text: [[String]], capacities: [Int], at time: Double) {
    guard text != self.text || capacities != self.capacities else { return }
    self.text = text
    self.capacities = capacities

    var updated: [Position: FlapTile] = [:]
    for (row, values) in text.enumerated() {
      for (column, value) in values.enumerated() where column < capacities.count {
        let characters = Array(value.uppercased().prefix(capacities[column]))
        for index in 0..<capacities[column] {
          let position = Position(row: row, column: column, index: index)
          let character = index < characters.count ? characters[index] : " "
          updated[position] = Self.tile(
            tiles[position] ?? FlapTile(),
            flippingTo: character,
            at: time,
            startingAt: time
              + Double(row) * 0.18
              + Double(column) * 0.1
              + Double(index) * 0.018
          )
        }
      }
    }
    tiles = updated
  }

  /// Returns the tile at a position, which is blank when that position is not on the board.
  func tile(row: Int, column: Int, index: Int) -> FlapTile {
    tiles[Position(row: row, column: column, index: index)] ?? FlapTile()
  }

  private static func tile(
    _ tile: FlapTile,
    flippingTo character: Character,
    at time: Double,
    startingAt startsAt: Double
  ) -> FlapTile {
    guard tile.target != character else { return tile }
    // A tile interrupted mid-flip continues from what it shows now.
    return FlapTile(current: tile.character(at: time), target: character, startsAt: startsAt)
  }
}

/// The tile sizes that follow from a column's font size.
struct SplitFlapMetrics: Equatable {
  /// The distance from the top of one row of tiles to the top of the next.
  static let rowHeight = 60
  /// The space between tiles in a column.
  static let tileGap = 2

  let fontSize: Int

  var tileWidth: Int { max(12, fontSize * 3 / 5) }

  /// Returns how many whole tiles fit in `width`.
  func capacity(forWidth width: Int) -> Int {
    max(0, (width + Self.tileGap) / (tileWidth + Self.tileGap))
  }

  /// Returns how many whole rows fit in `height`.
  static func rowCount(forHeight height: Int) -> Int {
    max(1, height / rowHeight)
  }
}
