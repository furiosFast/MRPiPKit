// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package. 6.4 ships with
// Xcode 27.1, whose iOS 27 SDK has the sample buffer receiver API: older toolchains reject the manifest instead of
// failing to compile it.

import PackageDescription

let package = Package(
    name: "MRPiPKit",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(name: "MRPiPKit", targets: ["MRPiPKit"]),
    ],
    targets: [
        .target(name: "MRPiPKit"),
    ],
    swiftLanguageModes: [.v5]
)
