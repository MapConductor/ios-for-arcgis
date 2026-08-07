import MapConductorCore
import XCTest

@testable import MapConductorForArcGIS

/// 2D `MapView` の tilt 擬似表現（`ArcGIS2DTiltEmulation`）のテスト。
///
/// 2D はカメラピッチを持てないため、tilt >= 0 は素通し（指定位置がそのまま画面中心）、
/// tilt < 0 は中心の前進 + ズーム補正で「カメラが見ている地表範囲」を近似する。
/// 式と定数は MapLibre / TomTom / Leaflet と共通。
final class ArcGIS2DTiltEmulationTests: XCTestCase {
    private let tokyo = GeoPoint(latitude: 35.6812, longitude: 139.7671, altitude: 0)

    /// tilt >= 0 は完全な素通し。見た目の傾きは `ArcGIS2DTiltModifier` が
    /// `MapView` 自体を回して作るので、中心もズームも触らない。
    func testNonNegativeTiltIsPassedThrough() {
        for tilt in [0.0, 30.0, 60.0] {
            let camera = MapCameraPosition(position: tokyo, zoom: 14, bearing: 45, tilt: tilt)
            let shifted = ArcGIS2DTiltEmulation.shiftedCamera(for: camera)

            XCTAssertEqual(shifted.center.latitude, tokyo.latitude, accuracy: 1e-9, "tilt=\(tilt)")
            XCTAssertEqual(shifted.center.longitude, tokyo.longitude, accuracy: 1e-9, "tilt=\(tilt)")
            XCTAssertEqual(shifted.zoom, 14, accuracy: 1e-9, "tilt=\(tilt)")
        }
    }

    /// 正の tilt の往復は恒等変換。
    func testPositiveTiltRoundTripsAsIdentity() {
        for tilt in [15.0, 30.0, 45.0, 60.0] {
            let camera = MapCameraPosition(position: tokyo, zoom: 14, bearing: 30, tilt: tilt)
            let shifted = ArcGIS2DTiltEmulation.shiftedCamera(for: camera)
            let restored = ArcGIS2DTiltEmulation.restoreLogicalCamera(
                center: shifted.center,
                zoom: shifted.zoom,
                bearing: 30,
                logicalTilt: tilt
            )
            XCTAssertEqual(restored.zoom, 14, accuracy: 1e-9, "tilt=\(tilt)")
            XCTAssertEqual(restored.position.latitude, tokyo.latitude, accuracy: 1e-9, "tilt=\(tilt)")
            XCTAssertEqual(restored.position.longitude, tokyo.longitude, accuracy: 1e-9, "tilt=\(tilt)")
        }
    }

    func testNegativeTiltShiftsCenterAlongBearingAndPullsZoomOut() {
        let camera = MapCameraPosition(position: tokyo, zoom: 14, bearing: 0, tilt: -60)
        let shifted = ArcGIS2DTiltEmulation.shiftedCamera(for: camera)

        // bearing = 0（真北）なので中心は北へ動く
        XCTAssertGreaterThan(shifted.center.latitude, tokyo.latitude)
        XCTAssertEqual(shifted.center.longitude, tokyo.longitude, accuracy: 1e-6)
        // 最大 tilt でのズームオフセットは -0.9
        XCTAssertEqual(shifted.zoom, 14 - 0.9, accuracy: 1e-9)
    }

    func testShiftDirectionFollowsBearing() {
        let east = ArcGIS2DTiltEmulation.shiftedCamera(
            for: MapCameraPosition(position: tokyo, zoom: 14, bearing: 90, tilt: -45)
        )
        XCTAssertGreaterThan(east.center.longitude, tokyo.longitude)
        // 大円に沿って東進するため緯度はわずかに下がる（数 m 程度）。経度の変化に比べれば無視できる。
        XCTAssertLessThan(abs(east.center.latitude - tokyo.latitude), 1e-3)

        let south = ArcGIS2DTiltEmulation.shiftedCamera(
            for: MapCameraPosition(position: tokyo, zoom: 14, bearing: 180, tilt: -45)
        )
        XCTAssertLessThan(south.center.latitude, tokyo.latitude)
    }

    /// 深い負 tilt ほど中心は遠くへ動く。
    func testShiftGrowsWithTiltMagnitude() {
        var previous = 0.0
        for tilt in [-15.0, -30.0, -45.0, -60.0] {
            let shifted = ArcGIS2DTiltEmulation.shiftedCamera(
                for: MapCameraPosition(position: tokyo, zoom: 14, bearing: 0, tilt: tilt)
            )
            let distance = Spherical.computeDistanceBetween(from: tokyo, to: shifted.center)
            XCTAssertGreaterThan(distance, previous, "tilt=\(tilt)")
            previous = distance
        }
    }

    /// 往復（論理 → Viewpoint → 論理）でズームは厳密に、位置はほぼ元へ戻る。
    ///
    /// 位置が厳密に一致しないのは、前進時は元の緯度、復元時はシフト後の緯度で高度を
    /// 計算するため（緯度依存の非対称性）。TomTom / MapLibre の負tilt 実装も同じ性質で、
    /// 実用上は tilt -60 でも十数 m。
    func testRoundTripRestoresLogicalCamera() {
        for tilt in [-15.0, -30.0, -45.0, -60.0] {
            for bearing in [0.0, 90.0, 217.0] {
                let label = "tilt=\(tilt) bearing=\(bearing)"
                let camera = MapCameraPosition(position: tokyo, zoom: 14, bearing: bearing, tilt: tilt)
                let shifted = ArcGIS2DTiltEmulation.shiftedCamera(for: camera)
                let restored = ArcGIS2DTiltEmulation.restoreLogicalCamera(
                    center: shifted.center,
                    zoom: shifted.zoom,
                    bearing: bearing,
                    logicalTilt: tilt
                )

                XCTAssertEqual(restored.zoom, 14, accuracy: 1e-9, label)
                let drift = Spherical.computeDistanceBetween(from: tokyo, to: restored.position)
                XCTAssertLessThan(drift, 30.0, "\(label): 復元位置のズレ \(drift)m")
            }
        }
    }

    /// 非負 tilt の復元は何もしない。
    func testRestoreIsNoOpForNonNegativeTilt() {
        let restored = ArcGIS2DTiltEmulation.restoreLogicalCamera(
            center: tokyo,
            zoom: 14,
            bearing: 30,
            logicalTilt: 45
        )
        XCTAssertEqual(restored.position.latitude, tokyo.latitude, accuracy: 1e-9)
        XCTAssertEqual(restored.position.longitude, tokyo.longitude, accuracy: 1e-9)
        XCTAssertEqual(restored.zoom, 14, accuracy: 1e-9)
    }
}
