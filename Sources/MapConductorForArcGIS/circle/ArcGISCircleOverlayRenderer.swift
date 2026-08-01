import ArcGIS
import MapConductorCore

@MainActor
final class ArcGISCircleOverlayRenderer: AbstractCircleOverlayRenderer<Graphic> {
    let circleLayer: GraphicsOverlay

    init(circleLayer: GraphicsOverlay) {
        self.circleLayer = circleLayer
        super.init()
    }

    override func createCircle(state: CircleState) async -> Graphic? {
        let graphic = Graphic(geometry: makeGeometry(state), symbol: makeSymbol(state))
        graphic.setAttributeValue(state.id, forKey: "id")
        graphic.setAttributeValue(state.zIndex ?? 0, forKey: "zIndex")
        circleLayer.addGraphic(graphic)
        return graphic
    }

    override func updateCircleProperties(
        circle: Graphic,
        current: CircleEntity<Graphic>,
        prev: CircleEntity<Graphic>
    ) async -> Graphic? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint
        if finger.center != prevFinger.center ||
            finger.radiusMeters != prevFinger.radiusMeters ||
            finger.geodesic != prevFinger.geodesic {
            circle.geometry = makeGeometry(current.state)
        }
        circle.symbol = makeSymbol(current.state)
        circle.setAttributeValue(current.state.zIndex ?? 0, forKey: "zIndex")
        return circle
    }

    override func removeCircle(entity: CircleEntity<Graphic>) async {
        if let circle = entity.circle {
            circleLayer.removeGraphic(circle)
        }
    }

    /// Builds the circle ring from the core `circleToRing` (shared across providers, WGS84
    /// radius), closed with `closeRing` and normalized to +/-180 for ArcGIS.
    private func makeGeometry(_ state: CircleState) -> Geometry {
        let points = closeRing(circleToRing(
            center: state.center,
            radiusMeters: state.radiusMeters,
            geodesic: state.geodesic
        ))
        .map { $0.normalize().toArcGISPoint(spatialReference: .wgs84) }
        return Polygon(points: points, spatialReference: .wgs84)
    }

    private func makeSymbol(_ state: CircleState) -> Symbol {
        let outline = SimpleLineSymbol(style: .solid, color: state.strokeColor, width: state.strokeWidth)
        return SimpleFillSymbol(style: .solid, color: state.fillColor, outline: outline)
    }
}
