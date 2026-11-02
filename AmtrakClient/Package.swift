// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "AmtrakClient",
  platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .macCatalyst(.v13)],
  products: [
    .library(name: "AmtrakClient", targets: ["AmtrakClient"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/apple/swift-log",
      .upToNextMajor(from: "1.5.0"),
    )
  ],
  targets: [
    .target(
      name: "AmtrakClient",
      dependencies: [
        .product(name: "Logging", package: "swift-log")
      ],
    )
  ],
)
