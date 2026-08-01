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
        graphic.setAttributeValue(state.zIndex, forKey: "zIndex")
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
        return polyline
    }

    override func removePolyline(entity: PolylineEntity<Graphic>) async {
        if let polyline = entity.polyline {
            polylineLayer.removeGraphic(polyline)
        }
    }

    override func onPostProcess() async {
        // 整列済みなら no-op（頂点ドラッグ等の高頻度 update で removeAllGraphics → 再追加による
        // ちらつきを避ける。android-for-arcgis と同じガード）。
        let graphics = Array(polylineLayer.graphics)
        guard graphics.count > 1 else { return }
        let sorted = graphics.sorted {
            (($0.attributeValue(forKey: "zIndex") as? Int) ?? 0) < (($1.attributeValue(forKey: "zIndex") as? Int) ?? 0)
        }
        if zip(graphics, sorted).allSatisfy({ $0 === $1 }) {
            return
        }
        polylineLayer.removeAllGraphics()
        sorted.forEach { polylineLayer.addGraphic($0) }
    }

    private func makeGeometry(_ state: PolylineState) -> Geometry {
        // 他プロバイダと同様、測地線・直線ともコアの共通補間で頂点列を生成し、ArcGIS には
        // 密な頂点列をそのまま渡す。生の頂点だと ArcGIS が辺を測地線として描くため、
        // 非 geodesic の直線が geodesic と同一形状になってしまう（android-sdk と同じ対応）。
        let points = state.geodesic
            ? createInterpolatePoints(state.points)
            : createLinearInterpolatePoints(state.points)
        return Polyline(
            points: points.map { $0.toArcGISPoint(spatialReference: .wgs84) },
            spatialReference: .wgs84
        )
    }

    private func makeSymbol(_ state: PolylineState) -> Symbol {
        SimpleLineSymbol(style: .solid, color: state.strokeColor, width: state.strokeWidth)
    }
}
