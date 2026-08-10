import ArcGIS
import CoreGraphics
import Foundation
import MapConductorCore

typealias ArcGISStrategyMarkerController = StrategyMarkerController<
    Graphic,
    AnyMarkerRenderingStrategy<Graphic>,
    ArcGISMarkerRenderer
>

final class ArcGISMapViewController: MapViewControllerProtocol {
    let holder: AnyMapViewHolder
    let typedHolder: ArcGISMapViewHolder
    let coroutine = CoroutineScope()

    /// この地図に紐づくオーバーレイコントローラの登録簿。
    /// 拡張モジュール（ヒートマップ、マーカークラスタリング等）がここに登録して
    /// カメラ変更を受け取る。`MapViewControllerProtocol` の要件。
    let overlayControllers = OverlayControllerRegistry()

    let markerController: ArcGISMarkerController
    let polylineController: ArcGISPolylineOverlayController
    let polygonController: ArcGISPolygonOverlayController
    let circleController: ArcGISCircleOverlayController
    let groundImageController: ArcGISGroundImageController
    let rasterLayerController: ArcGISRasterLayerController
    private let strategyMarkerControllerProvider: () -> ArcGISStrategyMarkerController?

    private var cameraMoveStartListener: OnCameraMoveHandler?
    private var cameraMoveListener: OnCameraMoveHandler?
    private var cameraMoveEndListener: OnCameraMoveHandler?

    /// ArcGIS はネイティブのカメラ範囲制限 API を持たないため、android-for-arcgis と同じく
    /// カメラ停止時に矩形内へクランプして再適用する方式で制限する。
    private let cameraRestrictionClamp = CameraRestrictionClamp()

    func setCameraRestriction(_ restriction: CameraRestriction?) {
        cameraRestrictionClamp.set(restriction)
    }

    /// カメラ停止時に制限違反を補正する。補正したら `true`。
    func applyCameraRestrictionCorrectionIfNeeded(_ current: MapCameraPosition) -> Bool {
        guard let corrected = cameraRestrictionClamp.correction(for: current) else { return false }
        moveCamera(position: corrected)
        return true
    }
    private var mapClickListener: OnMapEventHandler?
    private var mapLongClickListener: OnMapEventHandler?
    private var mapInitializedListener: OnMapInitializedHandler?
    private var mapDesignTypeChangeListener: ArcGISDesignTypeChangeHandler?
    private(set) var lastLogicalTilt: Double?

    init(
        holder: ArcGISMapViewHolder,
        markerController: ArcGISMarkerController,
        polylineController: ArcGISPolylineOverlayController,
        polygonController: ArcGISPolygonOverlayController,
        circleController: ArcGISCircleOverlayController,
        groundImageController: ArcGISGroundImageController,
        rasterLayerController: ArcGISRasterLayerController,
        strategyMarkerControllerProvider: @escaping () -> ArcGISStrategyMarkerController? = { nil }
    ) {
        self.typedHolder = holder
        self.holder = AnyMapViewHolder(holder)
        self.markerController = markerController
        self.polylineController = polylineController
        self.polygonController = polygonController
        self.circleController = circleController
        self.groundImageController = groundImageController
        self.rasterLayerController = rasterLayerController
        self.strategyMarkerControllerProvider = strategyMarkerControllerProvider
    }

    func clearOverlays() async {
        await markerController.clear()
        await groundImageController.clear()
        await polylineController.clear()
        await polygonController.clear()
        await circleController.clear()
        await rasterLayerController.clear()
    }

    func setCameraMoveStartListener(listener: OnCameraMoveHandler?) {
        cameraMoveStartListener = listener
    }

    func setCameraMoveListener(listener: OnCameraMoveHandler?) {
        cameraMoveListener = listener
    }

    func setCameraMoveEndListener(listener: OnCameraMoveHandler?) {
        cameraMoveEndListener = listener
    }

    func setMapClickListener(listener: OnMapEventHandler?) {
        mapClickListener = listener
    }

    func setMapLongClickListener(listener: OnMapEventHandler?) {
        mapLongClickListener = listener
    }

    func setMapInitializedListener(listener: OnMapInitializedHandler?) {
        mapInitializedListener = listener
    }

    func setMapDesignTypeChangeListener(listener: ArcGISDesignTypeChangeHandler?) {
        mapDesignTypeChangeListener = listener
    }

    func moveCamera(position: MapCameraPosition) {
        lastLogicalTilt = position.tilt
        typedHolder.mapView.lastCameraPosition = position
        Task {
            let viewportSize = typedHolder.mapView.viewportSize
            typedHolder.mapView.proxy?.proxy.setViewpointCamera(position.toArcGISCamera(viewportSize: viewportSize))
        }
    }

    func animateCamera(position: MapCameraPosition, duration: Long) {
        lastLogicalTilt = position.tilt
        typedHolder.mapView.lastCameraPosition = position
        Task {
            let viewportSize = typedHolder.mapView.viewportSize
            cameraMoveStartListener?(position)
            await typedHolder.mapView.proxy?.proxy.setViewpointCamera(
                position.toArcGISCamera(viewportSize: viewportSize),
                duration: Double(duration) / 1000
            )
            cameraMoveEndListener?(position)
        }
    }

    func fitBounds(bounds: GeoRectBounds, padding: Int) {
        guard let sw = bounds.southWest,
              let ne = bounds.northEast else { return }
        // SceneViewProxy exposes no padding-aware fit API (only the 2D MapViewProxy has
        // setViewpointGeometry(_:padding:)), so approximate the requested screen padding (points) by
        // expanding the target bounds proportionally to the padded fraction of the viewport before
        // framing them. With no viewport measured yet, this degrades to the unpadded fit.
        let rect = Self.boundsExpandedForPadding(
            minLon: sw.longitude,
            minLat: sw.latitude,
            maxLon: ne.longitude,
            maxLat: ne.latitude,
            padding: padding,
            viewportSize: typedHolder.mapView.viewportSize
        )
        let envelope = Envelope(
            xMin: rect.minLon,
            yMin: rect.minLat,
            xMax: rect.maxLon,
            yMax: rect.maxLat,
            spatialReference: .wgs84
        )
        let viewpoint = Viewpoint(boundingGeometry: envelope)
        Task {
            _ = await typedHolder.mapView.proxy?.proxy.setViewpoint(viewpoint)
        }
    }

    private static func boundsExpandedForPadding(
        minLon: Double,
        minLat: Double,
        maxLon: Double,
        maxLat: Double,
        padding: Int,
        viewportSize: CGSize?
    ) -> (minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        guard padding > 0, let size = viewportSize, size.width > 0, size.height > 0 else {
            return (minLon, minLat, maxLon, maxLat)
        }
        let p = CGFloat(padding)
        // Grow the framed extent so that `padding` points stay empty on each edge of the viewport.
        let ratioW = Double(size.width / max(1.0, size.width - 2 * p))
        let ratioH = Double(size.height / max(1.0, size.height - 2 * p))
        let centerLon = (minLon + maxLon) / 2.0
        let centerLat = (minLat + maxLat) / 2.0
        let halfWidth = (maxLon - minLon) / 2.0 * ratioW
        let halfHeight = (maxLat - minLat) / 2.0 * ratioH
        return (
            centerLon - halfWidth,
            centerLat - halfHeight,
            centerLon + halfWidth,
            centerLat + halfHeight
        )
    }

    func setMapDesignType(_ value: ArcGISMapDesignType) {
        typedHolder.map.basemap = Basemap(style: ArcGISDesign.toBasemapStyle(value))
        mapDesignTypeChangeListener?(value)
    }

    func notifyCameraMove(_ cameraPosition: MapCameraPosition) {
        typedHolder.mapView.lastCameraPosition = cameraPosition
        cameraMoveListener?(cameraPosition)
    }

    func notifyCameraMoveEnd(_ cameraPosition: MapCameraPosition) {
        // 登録済みオーバーレイ（拡張モジュール含む）へ伝播する。
        overlayControllers.dispatchCameraChanged(cameraPosition)
        typedHolder.mapView.lastCameraPosition = cameraPosition
        cameraMoveEndListener?(cameraPosition)
    }

    func notifyMapClick(_ point: GeoPoint) {
        mapClickListener?(point)
    }

    func notifyMapLongClick(_ point: GeoPoint) {
        mapLongClickListener?(point)
    }

    func notifyMapInitialized() {
        mapInitializedListener?(.MapCreated)
    }

    @MainActor
    func handleTap(screenPoint: CGPoint, mapPoint: Point?) async -> Bool {
        guard let touchPosition = mapPoint?.toGeoPoint() else { return false }

//        MapConductor manages all markers by our MakerManager.
//        We don't use SDK's semantic logic. Therefore, the following code does not work.
//
//        if let result = try? await typedHolder.mapView.proxy?.proxy.identify(
//            on: markerController.renderer.markerLayer,
//            screenPoint: screenPoint,
//           tolerance: 12,
//           maximumResults: 1
//        ),
//           let graphic = result.graphics.first,
//           let markerId = graphic.attributeValue(forKey: "id") as? String,
//           let entity = markerController.markerManager.getEntity(markerId) {
//            markerController.dispatchClick(state: entity.state)
//            return true
//        }

        
        // ヒット判定（アイコン矩形 + tapTolerance）は find() 側が行う。
        // 半径固定だと大きいアイコンは端が反応せず、小さいアイコンは離れていても反応してしまう。
        if let markerEntity = markerController.find(position: touchPosition) {
            markerController.dispatchClick(state: markerEntity.state)
            return true
        }

        if let strategyController = strategyMarkerControllerProvider(),
           let markerEntity = strategyController.find(position: touchPosition) {
            strategyController.dispatchClick(markerEntity.state)
            return true
        }
        
        // circle → groundImage → polyline → polygon の一本道。
        // 順序と先勝ちはコアの dispatchOverlayTap が持つ。
        // ここは移行前から正準順どおりだったので、順序の変更は無い。
        if dispatchOverlayTap(position: touchPosition) {
            return true
        }
        notifyMapClick(touchPosition)
        return false
    }

    @MainActor
    func handleLongPress(screenPoint: CGPoint, mapPoint: Point?) async {
        let touchPosition: GeoPoint?
        if let mapPoint {
            touchPosition = mapPoint.toGeoPoint()
        } else if let proxy = typedHolder.mapView.proxy?.proxy,
                  let resolvedPoint = try? await proxy.location(fromScreenPoint: screenPoint) {
            touchPosition = resolvedPoint.toGeoPoint()
        } else {
            touchPosition = nil
        }

        guard let touchPosition else { return }

        notifyMapLongClick(touchPosition)
    }

    @MainActor
    func handleMarkerDragStart(screenPoint: CGPoint, mapPoint: Point?) async -> Bool {
        if let proxy = typedHolder.mapView.proxy?.proxy,
           let result = try? await proxy.identify(
               on: markerController.renderer.markerLayer,
               screenPoint: screenPoint,
               tolerance: 12,
               returnPopupsOnly: false,
               maximumResults: nil
           ) {
            for graphic in result.graphics {
                guard let markerId = graphic.attributeValue(forKey: "id") as? String else { continue }
                if markerController.handleDragStart(markerId: markerId) {
                    return true
                }
            }
        }
        return markerController.handleDragStart(screenPoint: screenPoint)
    }

    @MainActor
    func handleMarkerDrag(screenPoint: CGPoint) async -> Bool {
        guard let touchPosition = await toGeoPoint(from: screenPoint) else { return false }
        return markerController.handleDrag(at: touchPosition)
    }

    @MainActor
    func handleMarkerDrag(mapPoint: Point) -> Bool {
        markerController.handleDrag(at: mapPoint.toGeoPoint())
    }

    @MainActor
    func handleMarkerDragEnd(screenPoint: CGPoint) async -> Bool {
        let touchPosition = await toGeoPoint(from: screenPoint)
        return markerController.handleDragEnd(at: touchPosition)
    }

    @MainActor
    func handleMarkerDragEnd(mapPoint: Point) -> Bool {
        markerController.handleDragEnd(at: mapPoint.toGeoPoint())
    }

    @MainActor
    func cancelMarkerDrag() -> Bool {
        markerController.cancelDrag()
    }

    @MainActor
    func finishMarkerDrag() -> Bool {
        markerController.handleDragEnd(at: nil)
    }

    @MainActor
    private func toGeoPoint(from screenPoint: CGPoint) async -> GeoPoint? {
        guard let proxy = typedHolder.mapView.proxy?.proxy,
              let point = try? await proxy.location(fromScreenPoint: screenPoint) else {
            return nil
        }
        return point.toGeoPoint()
    }
}
