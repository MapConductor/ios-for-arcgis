import ArcGIS
import CoreGraphics
import MapConductorCore

final class ArcGISSceneContainer {
    let scene: ArcGIS.Scene
    let graphicsOverlays: [GraphicsOverlay]
    var proxy: SceneViewProxyBox?
    var lastCameraPosition: MapCameraPosition
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

final class ArcGISMapViewHolder: MapViewHolderProtocol {
    let mapView: ArcGISSceneContainer
    let map: ArcGIS.Scene

    init(container: ArcGISSceneContainer) {
        self.mapView = container
        self.map = container.scene
    }

    func toScreenOffset(position: GeoPointProtocol) -> CGPoint? {
        nil
    }

    func fromScreenOffset(offset: CGPoint) async -> GeoPoint? {
        guard let point = try? await mapView.proxy?.proxy.location(fromScreenPoint: offset) else { return nil }
        return point.toGeoPoint()
    }

    func fromScreenOffsetSync(offset: CGPoint) -> GeoPoint? {
        nil
    }
}
