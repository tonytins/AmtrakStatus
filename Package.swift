// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "AmtrakStatus",
  platforms: [.macOS(.v10_15)],
  dependencies: [
    .package(path: "AmtrakClient"),
    .package(
      url: "https://github.com/tonytins/raylib-swift",
      branch: "main",
    ),
    .package(
      url: "https://github.com/apple/swift-argument-parser",
      .upToNextMajor(from: "1.5.0"),
    ),
    .package(
      url: "https://github.com/apple/swift-log",
      .upToNextMajor(from: "1.5.0"),
    ),
    .package(
      url: "https://github.com/tonytins/GitVersion",
      .upToNextMajor(from: "0.1.0"),
    ),
  ],
  targets: [
    .executableTarget(
      name: "AmtrakStatus",
      dependencies: [
        .product(name: "AmtrakClient", package: "AmtrakClient"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "GitVersion", package: "GitVersion"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "Raylib", package: "raylib-swift"),
      ],
      plugins: [
        .plugin(name: "GitVersionPlugin", package: "GitVersion")
      ],
    )
  ],
)
