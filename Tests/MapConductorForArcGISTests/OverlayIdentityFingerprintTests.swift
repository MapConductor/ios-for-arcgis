import MapConductorCore
import UIKit
import XCTest

@testable import MapConductorForArcGIS

/// ArcGIS の地図は `.task(id: overlayIdentityFingerprint)` が変わったときだけ `updateContent` を
/// 走らせる（他のプロバイダは body の評価ごとに走らせ、コレクタが差分を取る）。
///
/// 指紋が id しか見ていないと、**同じ id の新しい state** に差し替えても `updateContent` が走らず、
/// コレクタは古い state を購読したまま、新しい state の中身は地図に届かない。
@MainActor
final class OverlayIdentityFingerprintTests: XCTestCase {
    private func pt(_ lat: Double, _ lng: Double) -> GeoPoint { GeoPoint(latitude: lat, longitude: lng) }

    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }
    }

    private struct Shapes {
        let marker: MarkerState
        let polygon: PolygonState
        let polyline: PolylineState
        let circle: CircleState
        let ground: GroundImageState
        let raster: RasterLayerState
    }

    private func makeShapes(color: UIColor) -> Shapes {
        Shapes(
            marker: MarkerState(position: pt(35.68, 139.76), id: "M"),
            polygon: PolygonState(
                points: [pt(35.6, 139.7), pt(35.6, 139.8), pt(35.7, 139.8)],
                id: "PG",
                fillColor: color
            ),
            polyline: PolylineState(points: [pt(35.6, 139.7), pt(35.7, 139.8)], id: "PL", strokeColor: color),
            circle: CircleState(center: pt(35.65, 139.75), radiusMeters: 500, fillColor: color, id: "CI"),
            ground: GroundImageState(
                bounds: GeoRectBounds(southWest: pt(35.6, 139.7), northEast: pt(35.7, 139.8)),
                image: image(),
                id: "GI"
            ),
            raster: RasterLayerState(
                source: .urlTemplate(template: "https://example.invalid/{z}/{x}/{y}.png", tileSize: 256),
                id: "RL"
            )
        )
    }

    private func content(_ s: Shapes) -> MapViewContent {
        var c = MapViewContent()
        c.markers = [Marker(state: s.marker)]
        c.polygons = [Polygon(state: s.polygon)]
        c.polylines = [Polyline(state: s.polyline)]
        c.circles = [Circle(state: s.circle)]
        c.groundImages = [GroundImage(state: s.ground)]
        c.rasterLayers = [RasterLayer(state: s.raster)]
        return c
    }

    /// body が再評価されて content が組み直されても、同じ state なら指紋は変わらない
    /// （= `updateContent` は走らない。カメラ操作のたびに全件同期しないための前提）。
    func testSameStatesInARebuiltContentKeepTheFingerprint() {
        let shapes = makeShapes(color: .blue)
        XCTAssertEqual(content(shapes).overlayIdentityFingerprint, content(shapes).overlayIdentityFingerprint)
    }

    /// 同じ id の新しい state に差し替えたら、種類ごとに指紋が変わる。
    func testANewStateWithTheSameIdChangesTheFingerprint() {
        let old = makeShapes(color: .blue)
        let new = makeShapes(color: .red)
        let base = content(old).overlayIdentityFingerprint

        func replaced(_ edit: (inout MapViewContent) -> Void) -> Int {
            var c = content(old)
            edit(&c)
            return c.overlayIdentityFingerprint
        }

        XCTAssertNotEqual(base, replaced { $0.polygons = [Polygon(state: new.polygon)] }, "polygon")
        XCTAssertNotEqual(base, replaced { $0.polylines = [Polyline(state: new.polyline)] }, "polyline")
        XCTAssertNotEqual(base, replaced { $0.circles = [Circle(state: new.circle)] }, "circle")
        XCTAssertNotEqual(base, replaced { $0.groundImages = [GroundImage(state: new.ground)] }, "ground image")
        XCTAssertNotEqual(base, replaced { $0.rasterLayers = [RasterLayer(state: new.raster)] }, "raster layer")
        XCTAssertNotEqual(base, replaced { $0.markers = [Marker(state: new.marker)] }, "marker")
    }

    /// 同じ state の中身を書き換えても指紋は変わらない。in-place の変更は各 state の購読が届ける。
    func testMutatingAStateInPlaceKeepsTheFingerprint() {
        let shapes = makeShapes(color: .blue)
        let before = content(shapes).overlayIdentityFingerprint
        shapes.polygon.fillColor = .red
        shapes.marker.position = pt(35.70, 139.70)
        XCTAssertEqual(before, content(shapes).overlayIdentityFingerprint)
    }
}
