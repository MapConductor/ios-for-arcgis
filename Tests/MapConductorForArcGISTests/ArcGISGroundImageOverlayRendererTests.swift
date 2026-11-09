import ArcGIS
@_spi(MapConductorDriver) import MapConductorCore
import UIKit
import XCTest

@testable import MapConductorForArcGIS

/// GroundImage が 2D の MapView（`ArcGIS.Map`）にも載ること。
///
/// 2D は以前 `ArcGISGroundImageController(scene: nil)` で作っていて、レンダラは載せ先が
/// 無いので何も返さず、2D の地図に GroundImage は一度も表示されなかった。
@MainActor
final class ArcGISGroundImageOverlayRendererTests: XCTestCase {
    private func makeState() -> GroundImageState {
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
            opacity: 0.5,
            id: "ground-image-test"
        )
    }

    func testGroundImageIsAddedToAndRemovedFromA2DMap() async {
        let map = ArcGIS.Map()
        let renderer = ArcGISGroundImageOverlayRenderer(map: map)
        let state = makeState()

        let handle = await renderer.createGroundImage(state: state)

        XCTAssertNotNil(handle)
        XCTAssertEqual(map.operationalLayers.count, 1)
        XCTAssertTrue(map.operationalLayers.first === handle?.layer)
        XCTAssertEqual(handle?.layer.opacity ?? 0, 0.5, accuracy: 1e-6)

        await renderer.removeGroundImage(entity: GroundImageEntity(groundImage: handle, state: state))
        XCTAssertTrue(map.operationalLayers.isEmpty)
    }

    func testGroundImageIsAddedToA3DScene() async {
        let scene = ArcGIS.Scene()
        let renderer = ArcGISGroundImageOverlayRenderer(scene: scene)

        let handle = await renderer.createGroundImage(state: makeState())

        XCTAssertNotNil(handle)
        XCTAssertEqual(scene.operationalLayers.count, 1)
    }

    /// 2D でもラスターより上に載ること（重なり順の帯: ラスター < GroundImage）。
    /// GroundImage を先に載せ、あとからラスターが来ても下へ入る。
    func testGroundImageStaysAboveARasterOnA2DMap() async {
        let map = ArcGIS.Map()
        let renderer = ArcGISGroundImageOverlayRenderer(map: map)
        let handle = await renderer.createGroundImage(state: makeState())

        let raster = WebTiledLayer(urlTemplate: "https://example.invalid/{level}/{col}/{row}.png", subDomains: [])
        ArcGISOverlayStacking.add(raster, OverlayStacking.rasterKey(stateId: "raster-test", zIndex: 0), to: map)

        XCTAssertEqual(map.operationalLayers.count, 2)
        XCTAssertTrue(map.operationalLayers.first === raster)
        XCTAssertTrue(map.operationalLayers.last === handle?.layer)
    }
}
