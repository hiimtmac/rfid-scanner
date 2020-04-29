// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Run",
    products: [
        .executable(name: "Run", targets: ["Run"]),
        .library(name: "PiHardware", targets: ["PiHardware"])
    ],
    dependencies: [
        .package(url: "https://github.com/uraimo/SwiftyGPIO.git", from: "1.0.0"),
        .package(url: "https://github.com/dehesa/CodableCSV.git", from: "0.5.0")
    ],
    targets: [
        .target(name: "PiHardware", dependencies: [
            .product(name: "SwiftyGPIO", package: "SwiftyGPIO")
        ]),
        .target(name: "App", dependencies: [
            "PiHardware",
            .product(name: "SwiftyGPIO", package: "SwiftyGPIO"),
            .product(name: "CodableCSV", package: "CodableCSV")
        ]),
        .target(name: "Run", dependencies: [
            "App"
        ]),
        .testTarget(name: "AppTests", dependencies: ["App"]),
    ]
)
