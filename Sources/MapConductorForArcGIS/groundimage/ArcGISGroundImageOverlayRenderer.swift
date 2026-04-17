import ArcGIS
import MapConductorCore

@MainActor
final class ArcGISGroundImageOverlayRenderer: AbstractGroundImageOverlayRenderer<ArcGISGroundImageHandle> {
    private weak var scene: ArcGIS.Scene?
    private let tileServer: LocalTileServer

    init(scene: ArcGIS.Scene, tileServer: LocalTileServer = TileServerRegistry.get(forceNoStoreCache: true)) {
        self.scene = scene
        self.tileServer = tileServer
        super.init()
    }

    override func createGroundImage(state: GroundImageState) async -> ArcGISGroundImageHandle? {
        guard let scene else { return nil }
        let routeId = buildSafeRouteId(state.id)
        let provider = GroundImageTileProvider(tileSize: state.tileSize)
        provider.update(state: state, opacity: 1.0)
        tileServer.register(routeId: routeId, provider: provider)

        guard let handle = createHandle(routeId: routeId, generation: 0, cacheKey: tileCacheKey(state), provider: provider) else {
            tileServer.unregister(routeId: routeId)
            return nil
        }
        updateLayer(handle.layer, state)
        scene.addOperationalLayer(handle.layer)
        return handle
    }

    override func updateGroundImageProperties(
        groundImage: ArcGISGroundImageHandle,
        current: GroundImageEntity<ArcGISGroundImageHandle>,
        prev: GroundImageEntity<ArcGISGroundImageHandle>
    ) async -> ArcGISGroundImageHandle? {
        guard let scene else { return nil }
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
        scene.removeOperationalLayer(groundImage.layer)
        updateLayer(nextHandle.layer, current.state)
        scene.addOperationalLayer(nextHandle.layer)
        return nextHandle
    }

    override func removeGroundImage(entity: GroundImageEntity<ArcGISGroundImageHandle>) async {
        guard let handle = entity.groundImage else { return }
        scene?.removeOperationalLayer(handle.layer)
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
