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

    /// マーカーのアイコンを縦へ引き伸ばす倍率。
    ///
    /// 2D は `MapView` 自体を `rotation3DEffect` で傾けて tilt を表現するので（`ArcGIS2DTiltModifier`）、
    /// 地図の中身が縦に `cos(tilt)` 倍へ潰れる。マーカーだけは立って見えてほしいので、
    /// 先に `1 / cos(tilt)` 倍しておいて潰された後に元の高さになるようにする。
    /// 3D（SceneView）はビューを傾けないので常に 1。
    var markerVerticalStretch: Double { get }
}

extension ArcGISMapContext {
    var markerVerticalStretch: Double { 1.0 }
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
    /// `MapView` が縦へ cos(tilt) 倍に潰れるぶんを先に打ち消す。
    var markerVerticalStretch: Double {
        let angle = min(max(abs(visualTiltDegrees), 0.0), 60.0) * .pi / 180.0
        return 1.0 / max(cos(angle), 0.5)
    }

    func screenPoint(fromLocation point: Point) -> CGPoint? {
        proxy?.proxy.screenPoint(fromLocation: point)
    }

    func location(fromScreenPoint screenPoint: CGPoint) async -> GeoPoint? {
        guard let point = try? await proxy?.proxy.location(fromScreenPoint: screenPoint) else { return nil }
        return point.toGeoPoint()
    }
}
