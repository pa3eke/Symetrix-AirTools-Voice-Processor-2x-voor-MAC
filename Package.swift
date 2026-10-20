// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "VP2xMac", platforms: [.macOS(.v14)], products: [
    .library(name: "VP2xCore", targets: ["VP2xCore"]),
    .executable(name: "VP2xMac", targets: ["VP2xMac"])
], targets: [
    .target(name: "VP2xCore", resources: [.process("Resources")]),
    .executableTarget(name: "VP2xMac", dependencies: ["VP2xCore"]),
    .executableTarget(name: "VP2xChecks", dependencies: ["VP2xCore"], path: "Tests/VP2xCoreTests")
])
