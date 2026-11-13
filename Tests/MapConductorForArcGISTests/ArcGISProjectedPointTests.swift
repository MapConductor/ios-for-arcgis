import ArcGIS
import CoreGraphics
import MapConductorCore
import XCTest

@testable import MapConductorForArcGIS

/// 2D の投影座標は地図の空間参照で返る。
///
/// サンプルの 2D 地図は Web Mercator 固定なので、それ以外の空間参照（UTM・WGS84）は
/// ここでしか通らない。
@MainActor
final class ArcGISProjectedPointTests: XCTestCase {
    private let tokyo = GeoPoint(latitude: 35.681236, longitude: 139.767125)

    private func holder(_ spatialReference: SpatialReference) -> ArcGISMapView2DHolder {
        let container = ArcGISMapContainer2D(
            map: ArcGIS.Map(spatialReference: spatialReference),
            graphicsOverlays: [],
            cameraPosition: MapCameraPosition(position: tokyo, zoom: 12)
        )
        return ArcGISMapView2DHolder(container: container)
    }

    func testUtmZone54NReturnsEastingNorthingInMeters() throws {
        let holder = holder(try XCTUnwrap(SpatialReference(wkid: try XCTUnwrap(WKID(32654)))))
        XCTAssertEqual(holder.coordinateSystem, MapCoordinateSystem(code: "EPSG:32654", unit: .meters))

        let projected = try XCTUnwrap(holder.toProjectedPoint(tokyo))
        // 東京駅は中央子午線（東経 141 度）の西 1.23 度: 偽東距 500000 m から約 11 万 m 西。
        XCTAssertTrue((380_000.0...400_000.0).contains(projected.x), "easting \(projected.x)")
        XCTAssertTrue((3_940_000.0...3_960_000.0).contains(projected.y), "northing \(projected.y)")

        let back = try XCTUnwrap(holder.fromProjectedPoint(projected))
        XCTAssertEqual(back.latitude, tokyo.latitude, accuracy: 1e-7)
        XCTAssertEqual(back.longitude, tokyo.longitude, accuracy: 1e-7)
    }

    func testWgs84ReturnsDegrees() throws {
        let holder = holder(.wgs84)
        XCTAssertEqual(holder.coordinateSystem, .wgs84)
        let projected = try XCTUnwrap(holder.toProjectedPoint(tokyo))
        XCTAssertEqual(projected.x, tokyo.longitude, accuracy: 1e-9)
        XCTAssertEqual(projected.y, tokyo.latitude, accuracy: 1e-9)
    }

    func testWebMercatorMatchesTheCoreDefault() throws {
        let holder = holder(.webMercator)
        XCTAssertEqual(holder.coordinateSystem, .webMercator)
        let projected = try XCTUnwrap(holder.toProjectedPoint(tokyo))
        XCTAssertEqual(projected.x, 15558805.18, accuracy: 0.01)
        XCTAssertEqual(projected.y, 4256848.12, accuracy: 0.01)
    }
}
