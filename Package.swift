// swift-tools-version: 5.9
import Foundation
import PackageDescription

let frameworkLibraryType: Product.Library.LibraryType? =
    ProcessInfo.processInfo.environment["MAPCONDUCTOR_BUILD_XCFRAMEWORK"] == "1" ? .dynamic : nil
let usingLocalCore = FileManager.default.fileExists(atPath: "../ios-sdk-core/Package.swift")
let coreDependency: Package.Dependency = usingLocalCore
    ? .package(path: "../ios-sdk-core")
    : .package(url: "https://github.com/MapConductor/ios-sdk-core", from: "1.1.4")

let package = Package(
    name: "mapconductor-for-arcgis",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "MapConductorForArcGIS",
            type: frameworkLibraryType,
            targets: ["MapConductorForArcGIS"]
        ),
    ],
    dependencies: [
        coreDependency,
        .package(url: "https://github.com/Esri/arcgis-maps-sdk-swift", from: "200.8.0"),
    ],
    targets: [
        .target(
            name: "MapConductorForArcGIS",
            dependencies: [
                .product(name: "MapConductorCore", package: "ios-sdk-core"),
                .product(name: "ArcGIS", package: "arcgis-maps-sdk-swift"),
            ]
        ),
    ]
)
