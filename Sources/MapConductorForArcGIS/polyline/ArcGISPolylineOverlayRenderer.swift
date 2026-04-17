import ArcGIS
import MapConductorCore

final class ArcGISPolylineOverlayRenderer: AbstractPolylineOverlayRenderer<Graphic> {
    let polylineLayer: GraphicsOverlay

    init(polylineLayer: GraphicsOverlay) {
        self.polylineLayer = polylineLayer
        super.init()
    }

    override func createPolyline(state: PolylineState) async -> Graphic? {
        let graphic = Graphic(geometry: makeGeometry(state), symbol: makeSymbol(state))
        graphic.setAttributeValue(state.id, forKey: "id")
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

    private func makeGeometry(_ state: PolylineState) -> Geometry {
        Polyline(
            points: state.points.map { $0.toArcGISPoint(spatialReference: .wgs84) },
            spatialReference: .wgs84
        )
    }

    private func makeSymbol(_ state: PolylineState) -> Symbol {
        SimpleLineSymbol(style: .solid, color: state.strokeColor, width: state.strokeWidth)
    }
}
