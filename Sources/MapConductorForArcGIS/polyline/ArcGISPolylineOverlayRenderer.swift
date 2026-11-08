import ArcGIS
import MapConductorCore

@MainActor
final class ArcGISPolylineOverlayRenderer: AbstractPolylineOverlayRenderer<Graphic> {
    let polylineLayer: GraphicsOverlay

    init(polylineLayer: GraphicsOverlay) {
        self.polylineLayer = polylineLayer
        super.init()
    }

    override func createPolyline(state: PolylineState) async -> Graphic? {
        let graphic = Graphic(geometry: makeGeometry(state), symbol: makeSymbol(state))
        graphic.setAttributeValue(state.id, forKey: "id")
        ArcGISGraphicsZIndex.apply(graphic, state.zIndex)
        polylineLayer.addGraphic(graphic)
        return graphic
    }

    override func updatePolylineProperties(
        polyline: Graphic,
        current: PolylineEntity<Graphic>,
        prev: PolylineEntity<Graphic>
    ) async -> Graphic? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint
        if finger.points != prevFinger.points || finger.geodesic != prevFinger.geodesic {
            polyline.geometry = makeGeometry(current.state)
        }
        polyline.symbol = makeSymbol(current.state)
        if finger.zIndex != prevFinger.zIndex {
            ArcGISGraphicsZIndex.apply(polyline, current.state.zIndex)
        }
        return polyline
    }

    override func removePolyline(entity: PolylineEntity<Graphic>) async {
        if let polyline = entity.polyline {
            polylineLayer.removeGraphic(polyline)
        }
    }

    /// 重なり順は各 Graphic の zIndex が持つ（``ArcGISGraphicsZIndex``）。並べ替えは要らない。
    override func onPostProcess() async {}

    private func makeGeometry(_ state: PolylineState) -> Geometry {
        // 他プロバイダと同様、測地線・直線ともコアの共通補間で頂点列を生成し、ArcGIS には
        // 密な頂点列をそのまま渡す。生の頂点だと ArcGIS が辺を測地線として描くため、
        // 非 geodesic の直線が geodesic と同一形状になってしまう（android-sdk と同じ対応）。
        let points = state.geodesic
            ? WGS84Geodesic.createInterpolatePoints(state.points)
            : Planar.createInterpolatePoints(state.points)
        return Polyline(
            points: points.map { $0.toArcGISPoint(spatialReference: .wgs84) },
            spatialReference: .wgs84
        )
    }

    private func makeSymbol(_ state: PolylineState) -> Symbol {
        SimpleLineSymbol(style: .solid, color: state.strokeColor, width: state.strokeWidth)
    }
}
