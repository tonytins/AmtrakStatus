import Foundation

/// Keeps Amtraker's responses on disk, one file per URL, so they can be reused across launches.
///
/// Each file holds the response body exactly as Amtraker sent it, and its modification date is
/// when it was fetched. There is no format of its own: a file that no longer decodes is simply
/// fetched again.
public struct ResponseCache: Sendable {
  /// A saved response.
  public struct Entry: Equatable, Sendable {
    public var data: Data
    public var fetchedAt: Date
  }

  /// The folder the files are kept in. It is created when the first response is saved.
  public let directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  /// Returns a folder named `name` in this user's cache folder, such as
  /// `~/.cache/AmtrakStatus` on Linux or `~/Library/Caches/AmtrakStatus` on macOS, or `nil` when
  /// the system has no cache folder.
  public static func standardDirectory(named name: String) -> URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appendingPathComponent(name, isDirectory: true)
  }

  /// Saves `data` as the response for `url`, dated now. The file is replaced in one step, so a
  /// reader never sees half of it.
  public func save(_ data: Data, for url: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try data.write(to: file(for: url), options: .atomic)
  }

  /// Returns the saved response for `url`, or `nil` when there is none.
  public func entry(for url: URL) throws -> Entry? {
    let file = file(for: url)
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    let data = try Data(contentsOf: file)
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    guard let fetchedAt = attributes[.modificationDate] as? Date else { return nil }
    return Entry(data: data, fetchedAt: fetchedAt)
  }

  /// Deletes responses fetched before `date`, and returns how many were deleted. Each train
  /// number gets its own file, so without this they would pile up.
  @discardableResult
  public func removeEntries(fetchedBefore date: Date) throws -> Int {
    guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
    let files = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey]
    )
    var removed = 0
    for file in files where file.pathExtension == Self.fileExtension {
      let modified = try file.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate
      guard let modified, modified < date else { continue }
      try FileManager.default.removeItem(at: file)
      removed += 1
    }
    return removed
  }

  private static let fileExtension = "json"

  // Characters left as they are in file names. Everything else is percent-encoded, so each URL
  // has its own name that is safe on every platform.
  private static let fileNameCharacters = CharacterSet.alphanumerics
    .intersection(CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(127)))
    .union(CharacterSet(charactersIn: "-._"))

  /// Returns the file for `url`, such as `api.amtraker.com%2Fv3%2Ftrains%2F67.json`.
  func file(for url: URL) -> URL {
    let key = (url.host ?? "") + url.path + (url.query.map { "?" + $0 } ?? "")
    let name = key.addingPercentEncoding(withAllowedCharacters: Self.fileNameCharacters) ?? key
    return directory.appendingPathComponent(name).appendingPathExtension(Self.fileExtension)
  }
}
