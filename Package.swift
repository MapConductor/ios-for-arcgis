// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mapconductor-for-arcgis",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "MapConductorForArcGIS",
            targets: ["MapConductorForArcGIS"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/MapConductor/ios-sdk-core", from: "1.0.0"),
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
