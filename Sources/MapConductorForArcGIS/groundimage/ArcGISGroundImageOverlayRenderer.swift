import ArcGIS
@_spi(MapConductorDriver) import MapConductorCore

@MainActor
final class ArcGISGroundImageOverlayRenderer: AbstractGroundImageOverlayRenderer<ArcGISGroundImageHandle> {
    /// 載せ先（3D の Scene か 2D の Map）の操作レイヤーへの出し入れ。載せる位置は重なり順の帯
    /// （``ArcGISOverlayStacking``）で決める。載せ先が無くなっていれば false。
    private let addLayer: (Layer, OverlayStackKey) -> Bool
    private let removeLayer: (Layer) -> Void
    private let tileServer: LocalTileServer

    private init(
        addLayer: @escaping (Layer, OverlayStackKey) -> Bool,
        removeLayer: @escaping (Layer) -> Void,
        tileServer: LocalTileServer
    ) {
        self.addLayer = addLayer
        self.removeLayer = removeLayer
        self.tileServer = tileServer
        super.init()
    }

    convenience init(scene: ArcGIS.Scene?, tileServer: LocalTileServer = TileServerRegistry.get(forceNoStoreCache: true)) {
        self.init(
            addLayer: { [weak scene] layer, key in
                guard let scene else { return false }
                ArcGISOverlayStacking.add(layer, key, to: scene)
                return true
            },
            removeLayer: { [weak scene] layer in
                scene?.removeOperationalLayer(layer)
                // 取得中のタイル要求が片付くまで層を生かしておく（``ArcGISRetiredLayers``）。
                ArcGISRetiredLayers.retire(layer)
            },
            tileServer: tileServer
        )
    }

    /// 2D の MapView 用。以前の 2D は `scene: nil` で作っていて、GroundImage は一度も載らなかった。
    convenience init(map: ArcGIS.Map, tileServer: LocalTileServer = TileServerRegistry.get(forceNoStoreCache: true)) {
        self.init(
            addLayer: { [weak map] layer, key in
                guard let map else { return false }
                ArcGISOverlayStacking.add(layer, key, to: map)
                return true
            },
            removeLayer: { [weak map] layer in
                map?.removeOperationalLayer(layer)
                // 取得中のタイル要求が片付くまで層を生かしておく（``ArcGISRetiredLayers``）。
                ArcGISRetiredLayers.retire(layer)
            },
            tileServer: tileServer
        )
    }

    override func createGroundImage(state: GroundImageState) async -> ArcGISGroundImageHandle? {
        let routeId = buildSafeRouteId(state.id)
        let provider = GroundImageTileProvider(tileSize: state.tileSize)
        provider.update(state: state, opacity: 1.0)
        tileServer.register(routeId: routeId, provider: provider)

        guard let handle = createHandle(routeId: routeId, generation: 0, cacheKey: tileCacheKey(state), provider: provider) else {
            tileServer.unregister(routeId: routeId)
            return nil
        }
        updateLayer(handle.layer, state)
        guard addLayer(handle.layer, OverlayStackKey(.groundImage)) else {
            tileServer.unregister(routeId: routeId)
            return nil
        }
        return handle
    }

    override func updateGroundImageProperties(
        groundImage: ArcGISGroundImageHandle,
        current: GroundImageEntity<ArcGISGroundImageHandle>,
        prev: GroundImageEntity<ArcGISGroundImageHandle>
    ) async -> ArcGISGroundImageHandle? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint
        let tileNeedsRefresh = finger.bounds != prevFinger.bounds || finger.image != prevFinger.image || finger.tileSize != prevFinger.tileSize

        if !tileNeedsRefresh {
            updateLayer(groundImage.layer, current.state)
            return groundImage
        }

        let provider: GroundImageTileProvider
        if finger.tileSize != prevFinger.tileSize {
            provider = GroundImageTileProvider(tileSize: current.state.tileSize)
            tileServer.register(routeId: groundImage.routeId, provider: provider)
        } else {
            provider = groundImage.tileProvider
        }
        provider.update(state: current.state, opacity: 1.0)

        guard let nextHandle = createHandle(
            routeId: groundImage.routeId,
            generation: groundImage.generation + 1,
            cacheKey: tileCacheKey(current.state),
            provider: provider
        ) else {
            return nil
        }
        removeLayer(groundImage.layer)
        updateLayer(nextHandle.layer, current.state)
        guard addLayer(nextHandle.layer, OverlayStackKey(.groundImage)) else { return nil }
        return nextHandle
    }

    override func removeGroundImage(entity: GroundImageEntity<ArcGISGroundImageHandle>) async {
        guard let handle = entity.groundImage else { return }
        removeLayer(handle.layer)
        tileServer.unregister(routeId: handle.routeId)
    }

    private func updateLayer(_ layer: WebTiledLayer, _ state: GroundImageState) {
        layer.opacity = Float(min(max(state.opacity, 0), 1))
        layer.isVisible = true
    }

    private func createHandle(
        routeId: String,
        generation: Int,
        cacheKey: String,
        provider: GroundImageTileProvider
    ) -> ArcGISGroundImageHandle? {
        let template = tileServer
            .urlTemplate(routeId: routeId, tileSize: provider.tileSize, cacheKey: cacheKey)
            .replacingOccurrences(of: "{z}", with: "{level}")
            .replacingOccurrences(of: "{x}", with: "{col}")
            .replacingOccurrences(of: "{y}", with: "{row}")
        let layer = WebTiledLayer(urlTemplate: template, subDomains: [])
        return ArcGISGroundImageHandle(routeId: routeId, generation: generation, cacheKey: cacheKey, tileProvider: provider, layer: layer)
    }

    private func buildSafeRouteId(_ id: String) -> String {
        var out = "groundimage-"
        out.reserveCapacity(out.count + id.count)
        for ch in id {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                out.append(ch)
            } else {
                out.append("_")
            }
        }
        return out
    }

    private func tileCacheKey(_ state: GroundImageState) -> String {
        let finger = state.fingerPrint()
        return "\(finger.bounds)-\(finger.image)-\(finger.tileSize)-\(finger.extra)"
    }
}
