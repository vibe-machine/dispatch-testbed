// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "DispatchTestbed",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "DispatchTestbed", targets: ["DispatchTestbed"]),
  ],
  targets: [
    .target(name: "DispatchTestbed"),
    .testTarget(name: "DispatchTestbedTests", dependencies: ["DispatchTestbed"]),
  ]
)
