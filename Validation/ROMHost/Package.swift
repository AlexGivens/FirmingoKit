// swift-tools-version: 6.4
import PackageDescription

/// Separate macOS development host; the SDK library gains no executable or board dependency.
let package = Package(name: "ROMQualification", platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../..")], targets: [
        .executableTarget(name: "ROMQualification", dependencies: [.product(name: "FirmingoKit", package: "FirmingoKit")],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]),
        .testTarget(name: "ROMQualificationTests", dependencies: ["ROMQualification"])
    ])
