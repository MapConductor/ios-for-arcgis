import ArcGIS
import CoreGraphics
import MapConductorCore
import Foundation

public final class ArcGISSceneContainer {
    public let scene: ArcGIS.Scene
    public let graphicsOverlays: [GraphicsOverlay]
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

public final class ArcGISMapContainer2D {
    public let map: ArcGIS.Map
    public let graphicsOverlays: [GraphicsOverlay]
    var proxy: MapViewProxyBox?
    var lastCameraPosition: MapCameraPosition
    var viewportSize: CGSize?

    /// `ArcGIS2DTiltModifier` が `MapView` を傾けている角度（0...60）。
    /// マーカーを立てて見せるための縦補正に使う（`markerVerticalStretch`）。
    var visualTiltDegrees: Double = 0

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

public final class ArcGISMapView2DHolder: MapViewHolderProtocol {
    public let mapView: ArcGISMapContainer2D
    public let map: ArcGIS.Map

    init(container: ArcGISMapContainer2D) {
        self.mapView = container
        self.map = container.map
    }

    public func toScreenOffset(position: GeoPointProtocol) -> CGPoint? {
        guard let proxy = mapView.proxy?.proxy else { return nil }
        let point = position.toArcGISPoint(spatialReference: .wgs84)
        return proxy.screenPoint(fromLocation: point)
    }

    public func fromScreenOffset(offset: CGPoint) async -> GeoPoint? {
        guard let point = try? await mapView.proxy?.proxy.location(fromScreenPoint: offset) else { return nil }
        return point.toGeoPoint()
    }

    public func fromScreenOffsetSync(offset: CGPoint) -> GeoPoint? {
        nil
    }
}

// MARK: - 3D (SceneView) holder

public final class ArcGISMapViewHolder: MapViewHolderProtocol {
    public let mapView: ArcGISSceneContainer
    public let map: ArcGIS.Scene

    init(container: ArcGISSceneContainer) {
        self.mapView = container
        self.map = container.scene
    }

    public func toScreenOffset(position: GeoPointProtocol) -> CGPoint? {
        guard let proxy = mapView.proxy?.proxy else { return nil }
        let point = position.toArcGISPoint(spatialReference: .wgs84)
        return proxy.screenPoint(fromLocation: point)?.screenPoint
    }

    public func fromScreenOffset(offset: CGPoint) async -> GeoPoint? {
        guard let point = try? await mapView.proxy?.proxy.location(fromScreenPoint: offset) else { return nil }
        return point.toGeoPoint()
    }

    public func fromScreenOffsetSync(offset: CGPoint) -> GeoPoint? {
        nil
    }
}
