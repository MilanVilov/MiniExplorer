// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "MiniExplorer",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(name: "MiniExplorerCore", targets: ["MiniExplorerCore"]),
    .executable(name: "MiniExplorer", targets: ["MiniExplorer"]),
    .executable(name: "MiniExplorerCoreTests", targets: ["MiniExplorerCoreTests"]),
  ],
  targets: [
    .target(name: "MiniExplorerCore"),
    .executableTarget(
      name: "MiniExplorer",
      dependencies: ["MiniExplorerCore"]
    ),
    .executableTarget(
      name: "MiniExplorerCoreTests",
      dependencies: ["MiniExplorerCore"],
      path: "Tests/MiniExplorerCoreTests"
    ),
  ]
)
