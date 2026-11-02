// swift-tools-version: 6.4
import PackageDescription

/// App-owned orchestration shared by the Workbench UI and its explicit automation entry point.
let package = Package(name: "FirmingoWorkbenchSupport", platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "FirmingoWorkbenchCore", targets: ["FirmingoWorkbenchCore"])],
    dependencies: [.package(name: "FirmingoKit", path: "../..")], targets: [
        .target(name: "FirmingoWorkbenchCore", dependencies: [.product(name: "FirmingoKit", package: "FirmingoKit")],
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]),
        .testTarget(name: "FirmingoWorkbenchCoreTests", dependencies: ["FirmingoWorkbenchCore"])
    ])
