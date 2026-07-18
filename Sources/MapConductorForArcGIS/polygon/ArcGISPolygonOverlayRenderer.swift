import ArcGIS
import MapConductorCore

final class ArcGISPolygonOverlayRenderer: AbstractPolygonOverlayRenderer<Graphic> {
    let polygonLayer: GraphicsOverlay

    init(polygonLayer: GraphicsOverlay) {
        self.polygonLayer = polygonLayer
        super.init()
    }

    override func createPolygon(state: PolygonState) async -> Graphic? {
        let resolved = state.holes.count > 1 ? state.unionHoles() : state
        let graphic = Graphic(geometry: makeGeometry(resolved), symbol: makeSymbol(resolved))
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

        let shapeChanged = finger.points != prevFinger.points
            || finger.holes != prevFinger.holes
            || finger.geodesic != prevFinger.geodesic

        if shapeChanged {
            let resolved = current.state.holes.count > 1
                ? current.state.unionHoles()
                : current.state
            polygon.geometry = makeGeometry(resolved)
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
        let graphics = Array(polygonLayer.graphics)
        guard graphics.count > 1 else { return }

        let sorted = graphics.sorted {
            (($0.attributeValue(forKey: "zIndex") as? Int) ?? 0) < (($1.attributeValue(forKey: "zIndex") as? Int) ?? 0)
        }
        if zip(graphics, sorted).allSatisfy({ $0 === $1 }) {
            return
        }
        polygonLayer.removeAllGraphics()
        sorted.forEach { polygonLayer.addGraphic($0) }
    }

    // MARK: - Geometry / Symbol helpers

    private func makeGeometry(_ state: PolygonState) -> Geometry {
        let outer = ensureClockwiseRing(openRing(state.points))
        let holes = state.holes.map { ensureCounterClockwise(openRing($0)) }
        let parts = ([outer] + holes).map { ring in
            MutablePart(
                points: ring.map { $0.toArcGISPoint(spatialReference: .wgs84) },
                spatialReference: .wgs84
            )
        }
        return Polygon(parts: parts)
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
