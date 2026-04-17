import ArcGIS
import MapConductorCore

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

    private func makeGeometry(_ state: CircleState) -> Geometry {
        let points = stride(from: 0, through: 360, by: 8).map { bearing in
            calculateDestinationPoint(
                lat: state.center.latitude,
                lon: state.center.longitude,
                bearing: Double(bearing),
                distance: state.radiusMeters
            ).toArcGISPoint(spatialReference: .wgs84)
        }
        return Polygon(points: points, spatialReference: .wgs84)
    }

    private func makeSymbol(_ state: CircleState) -> Symbol {
        let outline = SimpleLineSymbol(style: .solid, color: state.strokeColor, width: state.strokeWidth)
        return SimpleFillSymbol(style: .solid, color: state.fillColor, outline: outline)
    }
}
