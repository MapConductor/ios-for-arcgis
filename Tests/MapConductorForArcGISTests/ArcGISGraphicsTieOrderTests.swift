import ArcGIS
import CoreGraphics
@_spi(MapConductorDriver) import MapConductorCore
import UIKit
import XCTest

@testable import MapConductorForArcGIS

/// 同じ zIndex の Graphic は、渡された順に重なること。
///
/// ArcGIS は同じ `Graphic.zIndex` の描く順を保証しない（API リファレンスは「通常は」足した順）。
/// android-for-arcgis ではタブレットの 2D で、zIndex=0 の 2 つの間に zIndex=1 が挟まると後から
/// 足した方が下に描かれた。iPad の 3D では、zIndex を上げて戻した Graphic が同じ zIndex の Graphic の
/// 上に来た。そこで (zIndex, 渡された順) の順位を `Graphic.zIndex` に書く。
/// 同じ値を書いている限り、順序は ArcGIS 任せになる。
@MainActor
final class ArcGISGraphicsTieOrderTests: XCTestCase {
    private func pt(_ lat: Double, _ lng: Double) -> GeoPoint { GeoPoint(latitude: lat, longitude: lng, altitude: 0) }

    private func rect(_ offset: Double) -> [GeoPoint] {
        [pt(35.0 + offset, 139.0 + offset), pt(35.0 + offset, 139.1 + offset),
         pt(35.1 + offset, 139.1 + offset), pt(35.1 + offset, 139.0 + offset)]
    }

    /// A(0) → Z(1) → B(0) の順に渡したとき、下から A < B < Z の順位が Graphic に書かれていること。
    private func assertSandwich(_ a: Graphic, _ z: Graphic, _ b: Graphic, _ what: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(a.zIndex, b.zIndex, "\(what): equal zIndex must keep the order passed (A before B)", file: file, line: line)
        XCTAssertLessThan(b.zIndex, z.zIndex, "\(what): zIndex=1 must stay above both", file: file, line: line)
    }

    func testPolygonsWithEqualZIndexKeepTheOrderPassed() async throws {
        let renderer = ArcGISPolygonOverlayRenderer(polygonLayer: GraphicsOverlay())
        let aRaw = await renderer.createPolygon(state: PolygonState(points: rect(0), id: "A", zIndex: 0))
        let zRaw = await renderer.createPolygon(state: PolygonState(points: rect(0.02), id: "Z", zIndex: 1))
        let bRaw = await renderer.createPolygon(state: PolygonState(points: rect(0.04), id: "B", zIndex: 0))
        assertSandwich(try XCTUnwrap(aRaw), try XCTUnwrap(zRaw), try XCTUnwrap(bRaw), "polygon")
    }

    func testCirclesWithEqualZIndexKeepTheOrderPassed() async throws {
        let renderer = ArcGISCircleOverlayRenderer(circleLayer: GraphicsOverlay())
        let aRaw = await renderer.createCircle(state: CircleState(center: pt(35.0, 139.0), radiusMeters: 1000, id: "A"))
        let zRaw = await renderer.createCircle(state: CircleState(center: pt(35.0, 139.005), radiusMeters: 1000, id: "Z", zIndex: 1))
        let bRaw = await renderer.createCircle(state: CircleState(center: pt(35.0, 139.01), radiusMeters: 1000, id: "B"))
        assertSandwich(try XCTUnwrap(aRaw), try XCTUnwrap(zRaw), try XCTUnwrap(bRaw), "circle")
    }

    func testPolylinesWithEqualZIndexKeepTheOrderPassed() async throws {
        let renderer = ArcGISPolylineOverlayRenderer(polylineLayer: GraphicsOverlay())
        let aRaw = await renderer.createPolyline(state: PolylineState(points: [pt(35.0, 139.0), pt(35.1, 139.1)], id: "A"))
        let zRaw = await renderer.createPolyline(state: PolylineState(points: [pt(35.1, 139.0), pt(35.0, 139.1)], id: "Z", zIndex: 1))
        let bRaw = await renderer.createPolyline(state: PolylineState(points: [pt(35.05, 139.0), pt(35.05, 139.1)], id: "B"))
        assertSandwich(try XCTUnwrap(aRaw), try XCTUnwrap(zRaw), try XCTUnwrap(bRaw), "polyline")
    }

    func testMarkersWithEqualZIndexKeepTheOrderPassed() async throws {
        let overlay = GraphicsOverlay()
        let context = StubMapContext()
        let renderer = ArcGISMarkerRenderer(markerLayer: overlay, container: context)
        let icon = DefaultMarkerIcon().toBitmapIcon()
        let states = [
            MarkerState(position: pt(35.0, 139.0), id: "A"),
            MarkerState(position: pt(35.0, 139.001), id: "Z", zIndex: 1),
            MarkerState(position: pt(35.0, 139.002), id: "B"),
        ]
        let graphics = await renderer.onAdd(data: states.map { MarkerOverlayAddParams(state: $0, bitmapIcon: icon) })
        let g = try graphics.map { try XCTUnwrap($0) }
        assertSandwich(g[0], g[1], g[2], "marker")
        _ = context
    }

    /// zIndex だけを変えて戻したとき、最初に渡された順に戻ること（並べ替えで順が入れ替わらない）。
    func testZIndexChangeKeepsTheFirstOrderPassed() async throws {
        let renderer = ArcGISPolygonOverlayRenderer(polygonLayer: GraphicsOverlay())
        let aState = PolygonState(points: rect(0), id: "A", zIndex: 0)
        let aRaw = await renderer.createPolygon(state: aState)
        let bRaw = await renderer.createPolygon(state: PolygonState(points: rect(0.04), id: "B", zIndex: 0))
        let a = try XCTUnwrap(aRaw)
        let b = try XCTUnwrap(bRaw)
        XCTAssertLessThan(a.zIndex, b.zIndex)

        let raised = PolygonState(points: rect(0), id: "A", zIndex: 1)
        _ = await renderer.updatePolygonProperties(
            polygon: a, current: PolygonEntity(polygon: a, state: raised), prev: PolygonEntity(polygon: a, state: aState)
        )
        XCTAssertGreaterThan(a.zIndex, b.zIndex, "raised A must draw above B")

        let lowered = PolygonState(points: rect(0), id: "A", zIndex: 0)
        _ = await renderer.updatePolygonProperties(
            polygon: a, current: PolygonEntity(polygon: a, state: lowered), prev: PolygonEntity(polygon: a, state: raised)
        )
        XCTAssertLessThan(a.zIndex, b.zIndex, "back at zIndex=0, A was passed first and must draw below B")
    }

    /// 順位表そのもの: 足す・移す・外すをどう混ぜても、(zIndex, 最初に置いた順) の順に狭義単調増加。
    func testRanksFollowZIndexThenFirstPlacement() {
        let table = ArcGISGraphicsZIndex()
        var rng = SystemRandomNumberGenerator()
        var live: [(graphic: Graphic, z: Int, seq: Int)] = []
        var seq = 0
        for step in 0..<2000 {
            let roll = Int.random(in: 0..<10, using: &rng)
            if roll < 5 || live.isEmpty {
                let g = Graphic()
                let z = Int.random(in: -2...2, using: &rng)
                table.place(g, z)
                live.append((g, z, seq)); seq += 1
            } else if roll < 8 {
                let i = Int.random(in: 0..<live.count, using: &rng)
                let z = Int.random(in: -2...2, using: &rng)
                table.place(live[i].graphic, z)
                live[i].z = z
            } else {
                let i = Int.random(in: 0..<live.count, using: &rng)
                table.forget(live[i].graphic)
                live.remove(at: i)
            }
            if step % 50 == 0 || step == 1999 {
                let ordered = live.sorted { $0.z != $1.z ? $0.z < $1.z : $0.seq < $1.seq }
                for (lower, upper) in zip(ordered, ordered.dropFirst()) {
                    XCTAssertLessThan(lower.graphic.zIndex, upper.graphic.zIndex, "step \(step)")
                }
                XCTAssertEqual(table.count, live.count)
            }
        }
        // まとめて外す
        let half = live.prefix(live.count / 2).map(\.graphic)
        table.forget(half)
        XCTAssertEqual(table.count, live.count - half.count)
    }
}

@MainActor
private final class StubMapContext: ArcGISMapContext {
    var viewportSize: CGSize? = nil
    var lastCameraPosition = MapCameraPosition(position: GeoPoint(latitude: 0, longitude: 0, altitude: 0), zoom: 1)
    func screenPoint(fromLocation point: Point) -> CGPoint? { nil }
    func location(fromScreenPoint screenPoint: CGPoint) async -> GeoPoint? { nil }
}
