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
    /// マーカーの縦補正（`markerVerticalStretch`）と座標の畳み込み
    /// （``fromInnerToSurface(_:)``）に使う。
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

    // MARK: - 内側 MapView ⇔ 入れ物の座標

    // `ArcGIS2DTiltModifier` は傾いているあいだ MapView を planeScale 倍へ広げて
    // 中央寄せし、X 軸まわりに回す（正射影）。SDK の `screenPoint` / `location` は
    // その**内側の座標系**で動くので、入れ物（可視領域）と付き合わせるときは
    // ここで畳む。OpenMobileMapsMapSurface の fromInnerToSurface と同じ役割だが、
    // あちらは UIKit の `convert(_:to:)` が変換を含めて畳んでくれるのに対し、
    // こちらの変形は SwiftUI 側にあるため式で畳む。
    //
    // 傾いていないとき（大半のページ）は scale = 1・角度 0 で恒等になる。

    private var visualAngleRadians: Double {
        min(max(abs(visualTiltDegrees), 0.0), 60.0) * .pi / 180.0
    }

    private var planeScale: CGFloat {
        visualTiltDegrees == 0 ? 1.0 : ArcGIS2DTiltEmulation.planeScale
    }

    /// 内側の `MapView` の座標 → 入れ物の座標。
    ///
    /// 中央寄せなのでずれは `(s-1)/2` 倍のビューポート、回転は正射影なので
    /// y が中心まわりに `cos(角度)` 倍へ潰れるだけ（x は変わらない）。
    func fromInnerToSurface(_ point: CGPoint) -> CGPoint {
        guard let size = viewportSize else { return point }
        let s = planeScale
        let x = point.x - (s - 1) * size.width / 2
        let innerCenterY = s * size.height / 2
        let y = size.height / 2 + (point.y - innerCenterY) * CGFloat(cos(visualAngleRadians))
        return CGPoint(x: x, y: y)
    }

    /// 入れ物の座標 → 内側の `MapView` の座標。``fromInnerToSurface(_:)`` の逆。
    func fromSurfaceToInner(_ point: CGPoint) -> CGPoint {
        guard let size = viewportSize else { return point }
        let s = planeScale
        let x = point.x + (s - 1) * size.width / 2
        let cosine = max(CGFloat(cos(visualAngleRadians)), 0.5)
        let y = s * size.height / 2 + (point.y - size.height / 2) / cosine
        return CGPoint(x: x, y: y)
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

    /// 地理座標 → 画面座標。
    ///
    /// SDK が返すのは**内側の `MapView` の座標**なので、
    /// ``ArcGISMapContainer2D/fromInnerToSurface(_:)`` で入れ物の座標へ畳んでから返す。
    /// 傾けているとき内側は拡大・回転しているため、畳まないと InfoBubble や
    /// マーカーアニメがずれる（OpenMobileMapsMapViewHolder と同じ規約）。
    public func toScreenOffset(position: GeoPointProtocol) -> CGPoint? {
        guard let proxy = mapView.proxy?.proxy else { return nil }
        let point = position.toArcGISPoint(spatialReference: .wgs84)
        guard let inner = proxy.screenPoint(fromLocation: point) else { return nil }
        return mapView.fromInnerToSurface(inner)
    }

    /// 画面座標 → 地理座標。入り口で入れ物の座標を内側の座標へ戻す（``toScreenOffset(position:)`` の逆）。
    public func fromScreenOffset(offset: CGPoint) async -> GeoPoint? {
        let inner = mapView.fromSurfaceToInner(offset)
        guard let point = try? await mapView.proxy?.proxy.location(fromScreenPoint: inner) else { return nil }
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
