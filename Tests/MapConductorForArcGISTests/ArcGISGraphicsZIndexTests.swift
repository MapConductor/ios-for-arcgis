import ArcGIS
@_spi(MapConductorDriver) import MapConductorCore
import XCTest

@testable import MapConductorForArcGIS

/// 帯の中の重なり順は zIndex で決まり、足した順に左右されないこと。
///
/// ArcGIS は同じ GraphicsOverlay の中を Graphic の `zIndex` の順に描き、同じ値なら足した順に描く。
/// 以前は zIndex を属性に書いてコレクションを並べ替えていたが（サークルは並べ替えもせず）、iPad では
/// zIndex=1 を先に、zIndex=0 を後に足すと、サークルとポリラインは 3D・2D とも zIndex=1 が下になった。
@MainActor
final class ArcGISGraphicsZIndexTests: XCTestCase {
    private func pt(_ lat: Double, _ lng: Double) -> GeoPoint { GeoPoint(latitude: lat, longitude: lng, altitude: 0) }

    private func rect(_ offset: Double) -> [GeoPoint] {
        [pt(35.0 + offset, 139.0 + offset), pt(35.0 + offset, 139.1 + offset),
         pt(35.1 + offset, 139.1 + offset), pt(35.1 + offset, 139.0 + offset)]
    }

    /// ArcGIS が `upper` を `lower` より上に描くか（zIndex、同じなら足した順）。
    private func drawsAbove(_ overlay: GraphicsOverlay, _ upper: Graphic, _ lower: Graphic) -> Bool {
        if upper.zIndex != lower.zIndex { return upper.zIndex > lower.zIndex }
        let graphics = Array(overlay.graphics)
        guard let u = graphics.firstIndex(where: { $0 === upper }),
              let l = graphics.firstIndex(where: { $0 === lower }) else { return false }
        return u > l
    }

    /// マーカーは同じ zIndex なら南が上。足した順には左右されず、zIndex を上げた方が勝つ。
    func testMarkersStackSouthInFrontAtTheSameZIndex() {
        let order = ArcGISGraphicsZIndex()
        let tie = { (lat: Double) in MarkerDrawOrder.key(zIndex: nil, position: self.pt(lat, 139)) }
        let south = Graphic()
        let north = Graphic()
        let raised = Graphic()
        order.place(south, nil, tie: tie(35.0))
        order.place(north, nil, tie: tie(35.1))
        XCTAssertGreaterThan(south.zIndex, north.zIndex, "south added first must still draw above north")
        order.place(raised, 1, tie: tie(36.0))
        XCTAssertGreaterThan(raised.zIndex, south.zIndex, "zIndex=1 must draw above zIndex=nil")
        // 北のマーカーが南へ動けば上に来る。
        order.place(north, nil, tie: tie(34.9))
        XCTAssertGreaterThan(north.zIndex, south.zIndex)
        XCTAssertGreaterThan(raised.zIndex, north.zIndex)
    }

    /// 地図を回して順位を付け直すと、同じ zIndex の中は画面で下が上になる。zIndex はそのまま勝つ。
    func testRetieAfterRotationPutsTheScreenLowerMarkerOnTop() {
        let order = ArcGISGraphicsZIndex()
        let tie = { (lat: Double, heading: Double) in
            MarkerDrawOrder.key(
                zIndex: nil,
                position: self.pt(lat, 139),
                frame: MarkerDrawOrder.Frame(heading: heading, originLongitude: 139)
            )
        }
        let south = Graphic()
        let north = Graphic()
        let raised = Graphic()
        order.place(south, nil, tie: tie(35.0, 0))
        order.place(north, nil, tie: tie(35.1, 0))
        order.place(raised, 1, tie: tie(35.05, 0))
        XCTAssertGreaterThan(south.zIndex, north.zIndex)
        // 南が上の画面（heading 180）では北が下に来るので上。
        order.retie([(south, tie(35.0, 180)), (north, tie(35.1, 180)), (raised, tie(35.05, 180))])
        XCTAssertGreaterThan(north.zIndex, south.zIndex)
        XCTAssertGreaterThan(raised.zIndex, north.zIndex)
        // 戻せば戻る。
        order.retie([(south, tie(35.0, 0)), (north, tie(35.1, 0)), (raised, tie(35.05, 0))])
        XCTAssertGreaterThan(south.zIndex, north.zIndex)
        XCTAssertGreaterThan(raised.zIndex, south.zIndex)
    }

    func testPolygonsStackByZIndexWhateverOrderTheyArrive() async throws {
        let overlay = GraphicsOverlay()
        let renderer = ArcGISPolygonOverlayRenderer(polygonLayer: overlay)
        let topState = PolygonState(points: rect(0), id: "top", zIndex: 1)
        let topRaw = await renderer.createPolygon(state: topState)
        let top = try XCTUnwrap(topRaw)
        let bottomRaw = await renderer.createPolygon(state: PolygonState(points: rect(0.05), id: "bottom", zIndex: 0))
        let bottom = try XCTUnwrap(bottomRaw)
        await renderer.onPostProcess()
        XCTAssertTrue(drawsAbove(overlay, top, bottom), "zIndex=1 added first must draw above zIndex=0")
        // iPad では並べ替えても描く順が変わらなかった。描く順を決めるのは Graphic の zIndex。
        XCTAssertGreaterThan(top.zIndex, bottom.zIndex, "the order must live in Graphic.zIndex")

        let lowered = PolygonState(points: rect(0), id: "top", zIndex: -1)
        _ = await renderer.updatePolygonProperties(
            polygon: top,
            current: PolygonEntity(polygon: top, state: lowered),
            prev: PolygonEntity(polygon: top, state: topState)
        )
        await renderer.onPostProcess()
        XCTAssertTrue(drawsAbove(overlay, bottom, top), "lowered polygon must draw below")
    }

    func testCirclesStackByZIndexWhateverOrderTheyArrive() async throws {
        let overlay = GraphicsOverlay()
        let renderer = ArcGISCircleOverlayRenderer(circleLayer: overlay)
        let topState = CircleState(center: pt(35.0, 139.0), radiusMeters: 1000, id: "top", zIndex: 1)
        let topRaw = await renderer.createCircle(state: topState)
        let top = try XCTUnwrap(topRaw)
        let bottomRaw = await renderer.createCircle(state: CircleState(center: pt(35.0, 139.01), radiusMeters: 1000, id: "bottom"))
        let bottom = try XCTUnwrap(bottomRaw)
        await renderer.onPostProcess()
        XCTAssertTrue(drawsAbove(overlay, top, bottom), "zIndex=1 added first must draw above the default zIndex")
        // iPad では並べ替えても描く順が変わらなかった。描く順を決めるのは Graphic の zIndex。
        XCTAssertGreaterThan(top.zIndex, bottom.zIndex, "the order must live in Graphic.zIndex")

        let lowered = CircleState(center: pt(35.0, 139.0), radiusMeters: 1000, id: "top", zIndex: -1)
        _ = await renderer.updateCircleProperties(
            circle: top,
            current: CircleEntity(circle: top, state: lowered),
            prev: CircleEntity(circle: top, state: topState)
        )
        await renderer.onPostProcess()
        XCTAssertTrue(drawsAbove(overlay, bottom, top), "lowered circle must draw below")
    }

    func testPolylinesStackByZIndexWhateverOrderTheyArrive() async throws {
        let overlay = GraphicsOverlay()
        let renderer = ArcGISPolylineOverlayRenderer(polylineLayer: overlay)
        let topState = PolylineState(points: [pt(35.0, 139.0), pt(35.1, 139.1)], id: "top", zIndex: 1)
        let topRaw = await renderer.createPolyline(state: topState)
        let top = try XCTUnwrap(topRaw)
        let bottomRaw = await renderer.createPolyline(
            state: PolylineState(points: [pt(35.1, 139.0), pt(35.0, 139.1)], id: "bottom", zIndex: 0)
        )
        let bottom = try XCTUnwrap(bottomRaw)
        await renderer.onPostProcess()
        XCTAssertTrue(drawsAbove(overlay, top, bottom), "zIndex=1 added first must draw above zIndex=0")
        // iPad では並べ替えても描く順が変わらなかった。描く順を決めるのは Graphic の zIndex。
        XCTAssertGreaterThan(top.zIndex, bottom.zIndex, "the order must live in Graphic.zIndex")

        let lowered = PolylineState(points: [pt(35.0, 139.0), pt(35.1, 139.1)], id: "top", zIndex: -1)
        _ = await renderer.updatePolylineProperties(
            polyline: top,
            current: PolylineEntity(polyline: top, state: lowered),
            prev: PolylineEntity(polyline: top, state: topState)
        )
        await renderer.onPostProcess()
        XCTAssertTrue(drawsAbove(overlay, bottom, top), "lowered polyline must draw below")
    }
}
