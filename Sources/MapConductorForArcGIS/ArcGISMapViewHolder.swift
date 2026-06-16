import ArcGIS
import CoreGraphics
import MapConductorCore
import Foundation

final class ArcGISSceneContainer {
    let scene: ArcGIS.Scene
    let graphicsOverlays: [GraphicsOverlay]
    var proxy: SceneViewProxyBox?
    var lastCameraPosition: MapCameraPosition
    var viewportSize: CGSize?
    // ArcGIS SDK uses weak_ptr internally, so these must be retained here to keep C++ objects alive.
    let baseSurface: ArcGIS.Surface
    let elevationSources: [ArcGIS.ElevationSource]

    init(
        scene: ArcGIS.Scene,
        graphicsOverlays: [GraphicsOverlay],
        cameraPosition: MapCameraPosition,
        baseSurface: ArcGIS.Surface,
        elevationSources: [ArcGIS.ElevationSource]
    ) {
        self.scene = scene
        self.graphicsOverlays = graphicsOverlays
        self.lastCameraPosition = cameraPosition
        self.baseSurface = baseSurface
        self.elevationSources = elevationSources
    }
}

final class SceneViewProxyBox {
    let proxy: SceneViewProxy

    init(_ proxy: SceneViewProxy) {
        self.proxy = proxy
    }
}

// MARK: - 2D (MapView) container and holder

final class ArcGISMapContainer2D {
    let map: ArcGIS.Map
    let graphicsOverlays: [GraphicsOverlay]
    var proxy: MapViewProxyBox?
    var lastCameraPosition: MapCameraPosition
    var viewportSize: CGSize?

    init(
        map: ArcGIS.Map,
        graphicsOverlays: [GraphicsOverlay],
        cameraPosition: MapCameraPosition
    ) {
        self.map = map
        self.graphicsOverlays = graphicsOverlays
        self.lastCameraPosition = cameraPosition
    }
}

final class MapViewProxyBox {
    let proxy: MapViewProxy

    init(_ proxy: MapViewProxy) {
        self.proxy = proxy
    }
}

final class ArcGISMapViewHolder2D: MapViewHolderProtocol {
    let mapView: ArcGISMapContainer2D
    let map: ArcGIS.Map

    init(container: ArcGISMapContainer2D) {
        self.mapView = container
        self.map = container.map
    }

    func toScreenOffset(position: GeoPointProtocol) -> CGPoint? {
        guard let proxy = mapView.proxy?.proxy else { return nil }
        let point = position.toArcGISPoint(spatialReference: .wgs84)
        return proxy.screenPoint(fromLocation: point)
    }

    func fromScreenOffset(offset: CGPoint) async -> GeoPoint? {
        guard let point = try? await mapView.proxy?.proxy.location(fromScreenPoint: offset) else { return nil }
        return point.toGeoPoint()
    }

    func fromScreenOffsetSync(offset: CGPoint) -> GeoPoint? {
        nil
    }
}

// MARK: - 3D (SceneView) holder

final class ArcGISMapViewHolder: MapViewHolderProtocol {
    let mapView: ArcGISSceneContainer
    let map: ArcGIS.Scene

    init(container: ArcGISSceneContainer) {
        self.mapView = container
        self.map = container.scene
    }

    func toScreenOffset(position: GeoPointProtocol) -> CGPoint? {
        guard let proxy = mapView.proxy?.proxy else { return nil }
        let point = position.toArcGISPoint(spatialReference: .wgs84)
        return proxy.screenPoint(fromLocation: point)?.screenPoint
    }

    func fromScreenOffset(offset: CGPoint) async -> GeoPoint? {
        guard let point = try? await mapView.proxy?.proxy.location(fromScreenPoint: offset) else { return nil }
        return point.toGeoPoint()
    }

    func fromScreenOffsetSync(offset: CGPoint) -> GeoPoint? {
        nil
    }
}
