import ArcGIS
import MapConductorCore

final class ArcGISPolygonOverlayRenderer: AbstractPolygonOverlayRenderer<Graphic> {
    let polygonLayer: GraphicsOverlay
    private weak var scene: ArcGIS.Scene?
    private var masks: [String: ArcGISMaskHandle] = [:]

    init(polygonLayer: GraphicsOverlay, scene: ArcGIS.Scene?) {
        self.polygonLayer = polygonLayer
        self.scene = scene
        super.init()
    }

    override func createPolygon(state: PolygonState) async -> Graphic? {
        if state.holes.isEmpty {
            removeMask(id: state.id)
            let graphic = Graphic(geometry: makeGeometry(state), symbol: makeSymbol(state))
            graphic.setAttributeValue(state.id, forKey: "id")
            graphic.setAttributeValue(state.zIndex, forKey: "zIndex")
            polygonLayer.addGraphic(graphic)
            return graphic
        } else {
            ensureMask(state: state)
            var noFillState = state
            let graphic = Graphic(
                geometry: makeGeometry(state, ignoreFill: true),
                symbol: makeSymbolStrokeOnly(state)
            )
            graphic.setAttributeValue(state.id, forKey: "id")
            graphic.setAttributeValue(state.zIndex, forKey: "zIndex")
            polygonLayer.addGraphic(graphic)
            return graphic
        }
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
        let hadHoles = !prev.state.holes.isEmpty
        let hasHoles = !current.state.holes.isEmpty

        if shapeChanged || hadHoles != hasHoles {
            polygonLayer.removeGraphic(polygon)
            removeMask(id: current.state.id)
            return await createPolygon(state: current.state)
        }

        if hasHoles {
            masks[current.state.id]?.tileRenderer.update(
                points: current.state.points,
                holes: current.state.holes,
                fillColor: current.state.fillColor,
                geodesic: current.state.geodesic
            )
            polygon.symbol = makeSymbolStrokeOnly(current.state)
        } else {
            polygon.geometry = makeGeometry(current.state)
            polygon.symbol = makeSymbol(current.state)
        }
        polygon.setAttributeValue(current.state.zIndex, forKey: "zIndex")
        return polygon
    }

    override func removePolygon(entity: PolygonEntity<Graphic>) async {
        if let polygon = entity.polygon {
            polygonLayer.removeGraphic(polygon)
        }
        removeMask(id: entity.state.id)
    }

    override func onPostProcess() async {
        let sorted = polygonLayer.graphics.sorted {
            (($0.attributeValue(forKey: "zIndex") as? Int) ?? 0) < (($1.attributeValue(forKey: "zIndex") as? Int) ?? 0)
        }
        polygonLayer.removeAllGraphics()
        sorted.forEach { polygonLayer.addGraphic($0) }
    }

    func unbind() {
        masks.values.forEach { handle in
            handle.layer.isVisible = false
            scene?.removeOperationalLayer(handle.layer)
            TileServerRegistry.get().unregister(routeId: handle.routeId)
        }
        masks.removeAll()
        scene = nil
    }

    // MARK: - Mask

    private func ensureMask(state: PolygonState) {
        let id = state.id
        if let existing = masks[id] {
            existing.tileRenderer.update(
                points: state.points,
                holes: state.holes,
                fillColor: state.fillColor,
                geodesic: state.geodesic
            )
            return
        }

        let tileRenderer = PolygonRasterTileRenderer(tileSize: 256)
        tileRenderer.update(
            points: state.points,
            holes: state.holes,
            fillColor: state.fillColor,
            geodesic: state.geodesic
        )

        let routeId = "polygon-raster-\(safeId(id))"
        let cacheKey = String(abs(routeId.hashValue))
        let tileServer = TileServerRegistry.get(forceNoStoreCache: true)
        tileServer.register(routeId: routeId, provider: tileRenderer)

        // WebTiledLayer uses {level}/{col}/{row} placeholders
        let xyzTemplate = tileServer.urlTemplate(routeId: routeId, tileSize: 256, cacheKey: cacheKey)
        let arcgisTemplate = xyzTemplate
            .replacingOccurrences(of: "{z}", with: "{level}")
            .replacingOccurrences(of: "{x}", with: "{col}")
            .replacingOccurrences(of: "{y}", with: "{row}")
        let layer = WebTiledLayer(urlTemplate: arcgisTemplate, subDomains: [])

        let handle = ArcGISMaskHandle(routeId: routeId, tileRenderer: tileRenderer, layer: layer)
        masks[id] = handle
        scene?.addOperationalLayer(layer)
    }

    private func removeMask(id: String) {
        guard let handle = masks.removeValue(forKey: id) else { return }
        handle.layer.isVisible = false
        scene?.removeOperationalLayer(handle.layer)
        TileServerRegistry.get().unregister(routeId: handle.routeId)
    }

    private func safeId(_ id: String) -> String {
        id.map { ch in
            ch.isLetter || ch.isNumber || ch == "-" || ch == "_" ? String(ch) : "_"
        }.joined()
    }

    // MARK: - Geometry / Symbol helpers

    private func makeGeometry(_ state: PolygonState, ignoreFill: Bool = false) -> Geometry {
        let outer = ensureCounterClockwise(closedRing(state.points))
        let holes = ignoreFill ? [] : state.holes.map { ensureClockwiseRing(closedRing($0)) }
        let parts = ([outer] + holes).map { ring in
            MutablePart(
                points: ring.map { $0.toArcGISPoint(spatialReference: .wgs84) },
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

    private func makeSymbolStrokeOnly(_ state: PolygonState) -> Symbol {
        let outline = SimpleLineSymbol(style: .solid, color: state.strokeColor, width: state.strokeWidth)
        return SimpleFillSymbol(style: .solid, color: .clear, outline: outline)
    }
}

private struct ArcGISMaskHandle {
    let routeId: String
    let tileRenderer: PolygonRasterTileRenderer
    let layer: WebTiledLayer
}
