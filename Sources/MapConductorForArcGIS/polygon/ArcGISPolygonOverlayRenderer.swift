import ArcGIS
import MapConductorCore

final class ArcGISPolygonOverlayRenderer: AbstractPolygonOverlayRenderer<Graphic> {
    let polygonLayer: GraphicsOverlay

    init(polygonLayer: GraphicsOverlay) {
        self.polygonLayer = polygonLayer
        super.init()
    }

    override func createPolygon(state: PolygonState) async -> Graphic? {
        let graphic = Graphic(geometry: makeGeometry(state), symbol: makeSymbol(state))
        graphic.setAttributeValue(state.id, forKey: "id")
        graphic.setAttributeValue(state.zIndex, forKey: "zIndex")
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
        if finger.points != prevFinger.points || finger.holes != prevFinger.holes || finger.geodesic != prevFinger.geodesic {
            polygon.geometry = makeGeometry(current.state)
        }
        polygon.symbol = makeSymbol(current.state)
        polygon.setAttributeValue(current.state.zIndex, forKey: "zIndex")
        return polygon
    }

    override func removePolygon(entity: PolygonEntity<Graphic>) async {
        if let polygon = entity.polygon {
            polygonLayer.removeGraphic(polygon)
        }
    }

    override func onPostProcess() async {
        let sorted = polygonLayer.graphics.sorted {
            (($0.attributeValue(forKey: "zIndex") as? Int) ?? 0) < (($1.attributeValue(forKey: "zIndex") as? Int) ?? 0)
        }
        polygonLayer.removeAllGraphics()
        sorted.forEach { polygonLayer.addGraphic($0) }
    }

    private func makeGeometry(_ state: PolygonState) -> Geometry {
        let parts = ([state.points] + state.holes).map { points in
            MutablePart(
                points: closedRing(points).map { $0.toArcGISPoint(spatialReference: .wgs84) },
                spatialReference: .wgs84
            )
        }
        return Polygon(parts: parts)
    }

    private func closedRing(_ points: [GeoPointProtocol]) -> [GeoPointProtocol] {
        guard let first = points.first, let last = points.last else { return points }
        if first.latitude == last.latitude && first.longitude == last.longitude {
            return points
        }
        return points + [first]
    }

    private func makeSymbol(_ state: PolygonState) -> Symbol {
        let outline = SimpleLineSymbol(style: .solid, color: state.strokeColor, width: state.strokeWidth)
        return SimpleFillSymbol(style: .solid, color: state.fillColor, outline: outline)
    }
}
