import ArcGIS
import CoreGraphics
import MapConductorCore

/// Common protocol for both 3D (SceneView) and 2D (MapView) map containers.
@MainActor
protocol ArcGISMapContext: AnyObject {
    var viewportSize: CGSize? { get }
    var lastCameraPosition: MapCameraPosition { get set }
    func screenPoint(fromLocation point: Point) -> CGPoint?
    func location(fromScreenPoint screenPoint: CGPoint) async -> GeoPoint?
}

extension ArcGISSceneContainer: ArcGISMapContext {
    func screenPoint(fromLocation point: Point) -> CGPoint? {
        proxy?.proxy.screenPoint(fromLocation: point)?.screenPoint
    }

    func location(fromScreenPoint screenPoint: CGPoint) async -> GeoPoint? {
        guard let point = try? await proxy?.proxy.location(fromScreenPoint: screenPoint) else { return nil }
        return point.toGeoPoint()
    }
}

extension ArcGISMapContainer2D: ArcGISMapContext {
    func screenPoint(fromLocation point: Point) -> CGPoint? {
        proxy?.proxy.screenPoint(fromLocation: point)
    }

    func location(fromScreenPoint screenPoint: CGPoint) async -> GeoPoint? {
        guard let point = try? await proxy?.proxy.location(fromScreenPoint: screenPoint) else { return nil }
        return point.toGeoPoint()
    }
}
