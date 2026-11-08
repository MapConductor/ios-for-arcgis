import ArcGIS
import Foundation
import MapConductorCore

// ArcGIS の Graphic / GraphicsOverlay 変更は他レンダラ（marker など）と同様に MainActor 上で
// 行う。nonisolated async のままだと global executor 上で走り、SceneView への反映が不安定になる。
@MainActor
final class ArcGISPolygonOverlayRenderer: AbstractPolygonOverlayRenderer<Graphic> {
    let polygonLayer: GraphicsOverlay

    init(polygonLayer: GraphicsOverlay) {
        self.polygonLayer = polygonLayer
        super.init()
    }

    override func createPolygon(state: PolygonState) async -> Graphic? {
        let resolved = await resolveHoles(state)
        let graphic = Graphic(geometry: makeGeometry(resolved), symbol: makeSymbol(resolved))
        graphic.setAttributeValue(state.id, forKey: "id")
        ArcGISGraphicsZIndex.apply(graphic, state.zIndex)
        polygonLayer.addGraphic(graphic)
        return graphic
    }

    override func updatePolygonProperties(
        polygon: Graphic,
        current: PolygonEntity<Graphic>,
        prev: PolygonEntity<Graphic>
    ) async -> Graphic? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        let shapeChanged = finger.points != prevFinger.points
            || finger.holes != prevFinger.holes
            || finger.geodesic != prevFinger.geodesic

        if shapeChanged {
            polygon.geometry = makeGeometry(await resolveHoles(current.state))
        }

        // Android 実装と同様、ドラッグで geometry だけが変わった場合は symbol を作り直さない。
        // ArcGIS の Graphic に不要な更新を加えないことで、連続ドラッグ時の描画負荷を抑える。
        if finger.fillColor != prevFinger.fillColor
            || finger.strokeColor != prevFinger.strokeColor
            || finger.strokeWidth != prevFinger.strokeWidth {
            polygon.symbol = makeSymbol(current.state)
        }
        if finger.zIndex != prevFinger.zIndex {
            ArcGISGraphicsZIndex.apply(polygon, current.state.zIndex)
        }
        return polygon
    }

    override func removePolygon(entity: PolygonEntity<Graphic>) async {
        if let polygon = entity.polygon {
            polygonLayer.removeGraphic(polygon)
        }
    }

    /// 重なり順は各 Graphic の zIndex が持つ（``ArcGISGraphicsZIndex``）。並べ替えは要らない。
    override func onPostProcess() async {}

    // MARK: - Geometry / Symbol helpers

    /// 複数の穴が重なっている場合は結合（union）して重複を解消する。
    /// 他プロバイダ（Mapbox/MapLibre/HERE/Google）と同じ `unionHoles()` を用いる。
    ///
    /// ArcGIS のマルチパートポリゴンは穴リングを個別のパートとして扱うため、重なった穴を
    /// そのまま渡すと重なり部分が再び塗られる。コンポーネント層（`Polygon`）のユニオンは
    /// state 1 インスタンスにつき 1 回きりで、頂点ドラッグ後の `state.holes` 差し替えには
    /// 追従しないため、android-for-arcgis と同じくここでも結合する。
    ///
    /// android-for-arcgis が `withContext(Dispatchers.Default)` で逃がしているのと同じく、
    /// 平面アレンジメント（辺数に対して O(n²)）は MainActor の外で回す。
    private func resolveHoles(_ state: PolygonState) async -> PolygonState {
        guard state.holes.count > 1 else { return state }
        return await state.unionHolesInBackground()
    }

    private func makeGeometry(_ state: PolygonState) -> Geometry {
        // リングは閉じてから密度化する。開いたまま渡すと閉じる辺（末尾 → 先頭）が補間されず、
        // geodesic では直線の弦に、非 geodesic では ArcGIS の測地線の辺になる（他の辺と形が揃わない）。
        // react-for-arcgis / android-for-arcgis と同じ（closeRing してから密度化し、最後に openRing で開く）。
        let outer = ensureClockwiseRing(openRing(toRing(closeRing(state.points), geodesic: state.geodesic)))
        let holes = state.holes.map {
            ensureCounterClockwise(openRing(toRing(closeRing($0), geodesic: state.geodesic)))
        }
        let parts = ([outer] + holes).map { ring in
            MutablePart(
                points: ring.map { $0.toArcGISPoint(spatialReference: .wgs84) },
                spatialReference: .wgs84
            )
        }
        return Polygon(parts: parts)
    }

    /// リングをコア共通の補間で密度化する。生の頂点だと ArcGIS が辺を測地線として描くため、
    /// 非 geodesic の直線辺は線形補間で近似する（android-sdk と同じ対応）。geodesic は
    /// 世界マスク級のリングが過密になって描画に失敗しないよう粗めの分割長にする。
    private func toRing(_ points: [GeoPointProtocol], geodesic: Bool) -> [GeoPointProtocol] {
        geodesic
            ? WGS84Geodesic.createInterpolatePoints(points, maxSegmentLength: 100_000.0)
            : Planar.createInterpolatePoints(points)
    }

    private func openRing(_ points: [GeoPointProtocol]) -> [GeoPointProtocol] {
        guard let first = points.first, let last = points.last else { return points }
        if first.latitude == last.latitude && first.longitude == last.longitude {
            return Array(points.dropLast())
        }
        return points
    }

    private func makeSymbol(_ state: PolygonState) -> Symbol {
        let outline = SimpleLineSymbol(style: .solid, color: state.strokeColor, width: state.strokeWidth)
        return SimpleFillSymbol(style: .solid, color: state.fillColor, outline: outline)
    }
}
