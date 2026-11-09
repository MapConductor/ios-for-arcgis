import ArcGIS
@_spi(MapConductorDriver) import MapConductorCore
import UIKit
import XCTest

@testable import MapConductorForArcGIS

/// 地図から外したタイル層が、すぐには解放されないこと。
///
/// ArcGIS は外した層にも取得中だったタイル要求の失敗を知らせに来る。層が解放済みだと
/// ArcGIS のワーカースレッドで落ちる（iPad の 2D で、ラスターと GroundImage を続けて足し外しして
/// 11 回中 6 回）。外した層は ``ArcGISRetiredLayers`` がしばらく持つ。
@MainActor
final class ArcGISRetiredLayersTests: XCTestCase {
    private var savedHold: TimeInterval = 0

    override func setUp() async throws {
        savedHold = ArcGISRetiredLayers.holdSeconds
        ArcGISRetiredLayers.holdSeconds = 0.3
    }

    override func tearDown() async throws {
        ArcGISRetiredLayers.holdSeconds = savedHold
    }

    private func groundImageState() -> GroundImageState {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return GroundImageState(
            bounds: GeoRectBounds(
                southWest: GeoPoint(latitude: 40.70, longitude: -74.26, altitude: 0),
                northEast: GeoPoint(latitude: 40.78, longitude: -74.12, altitude: 0)
            ),
            image: image,
            id: "retired-ground-image"
        )
    }

    private func settle(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func testRemovedRasterLayerOutlivesItsRemovalForAWhile() async {
        let map = ArcGIS.Map()
        let renderer = ArcGISRasterLayerOverlayRenderer(map: map)
        let state = RasterLayerState(
            source: .urlTemplate(template: "https://example.invalid/{z}/{x}/{y}.png", tileSize: 256),
            id: "retired-raster"
        )
        weak var weakLayer: Layer?
        do {
            let layer = await renderer.createLayer(state: state)
            weakLayer = layer
            XCTAssertEqual(map.operationalLayers.count, 1)
            await renderer.removeLayer(entity: RasterLayerEntity(layer: layer, state: state))
        }
        XCTAssertTrue(map.operationalLayers.isEmpty)
        XCTAssertNotNil(weakLayer, "a removed tiled layer must stay alive while its tile requests settle")

        await settle(1.0)
        XCTAssertNil(weakLayer, "the removed layer must be let go afterwards")
    }

    func testRemovedGroundImageLayerOutlivesItsRemovalForAWhile() async {
        let map = ArcGIS.Map()
        let renderer = ArcGISGroundImageOverlayRenderer(map: map)
        let state = groundImageState()
        weak var weakLayer: Layer?
        do {
            let handle = await renderer.createGroundImage(state: state)
            weakLayer = handle?.layer
            await renderer.removeGroundImage(entity: GroundImageEntity(groundImage: handle, state: state))
        }
        XCTAssertTrue(map.operationalLayers.isEmpty)
        XCTAssertNotNil(weakLayer, "a removed ground image layer must stay alive while its tile requests settle")

        await settle(1.0)
        XCTAssertNil(weakLayer, "the removed layer must be let go afterwards")
    }
}
