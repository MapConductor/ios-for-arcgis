import ArcGIS
import Foundation
import MapConductorCore

final class ArcGISMapViewController: MapViewControllerProtocol {
    let holder: AnyMapViewHolder
    let typedHolder: ArcGISMapViewHolder
    let coroutine = CoroutineScope()

    let markerController: ArcGISMarkerController
    let polylineController: ArcGISPolylineOverlayController
    let polygonController: ArcGISPolygonOverlayController
    let circleController: ArcGISCircleOverlayController
    let groundImageController: ArcGISGroundImageController
    let rasterLayerController: ArcGISRasterLayerController

    private var cameraMoveStartListener: OnCameraMoveHandler?
    private var cameraMoveListener: OnCameraMoveHandler?
    private var cameraMoveEndListener: OnCameraMoveHandler?
    private var mapClickListener: OnMapEventHandler?
    private var mapLongClickListener: OnMapEventHandler?
    private var mapInitializedListener: OnMapInitializedHandler?
    private var mapDesignTypeChangeListener: ArcGISDesignTypeChangeHandler?

    init(
        holder: ArcGISMapViewHolder,
        markerController: ArcGISMarkerController,
        polylineController: ArcGISPolylineOverlayController,
        polygonController: ArcGISPolygonOverlayController,
        circleController: ArcGISCircleOverlayController,
        groundImageController: ArcGISGroundImageController,
        rasterLayerController: ArcGISRasterLayerController
    ) {
        self.typedHolder = holder
        self.holder = AnyMapViewHolder(holder)
        self.markerController = markerController
        self.polylineController = polylineController
        self.polygonController = polygonController
        self.circleController = circleController
        self.groundImageController = groundImageController
        self.rasterLayerController = rasterLayerController
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
        typedHolder.mapView.lastCameraPosition = position
        Task {
            let viewportSize = typedHolder.mapView.viewportSize
            typedHolder.mapView.proxy?.proxy.setViewpointCamera(position.toArcGISCamera(viewportSize: viewportSize))
        }
    }

    func animateCamera(position: MapCameraPosition, duration: Long) {
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
        let envelope = Envelope(
            xMin: sw.longitude,
            yMin: sw.latitude,
            xMax: ne.longitude,
            yMax: ne.latitude,
            spatialReference: .wgs84
        )
        let viewpoint = Viewpoint(boundingGeometry: envelope)
        Task {
            _ = await typedHolder.mapView.proxy?.proxy.setViewpoint(viewpoint)
        }
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
        let clickRadiusPt: CGFloat = 44
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

        
        if let markerEntity = markerController.find(position: touchPosition),
           let markerPoint = toScreenPoint(from: markerEntity.state.position) {
            let dist = hypot(screenPoint.x - markerPoint.x, screenPoint.y - markerPoint.y)
            if dist < clickRadiusPt {
                markerController.dispatchClick(state: markerEntity.state)
                return true
            }
        }
        
        if let circle = circleController.find(position: touchPosition) {
            circleController.dispatchClick(event: CircleEvent(state: circle.state, clicked: touchPosition))
            return true
        }
        if let groundImage = groundImageController.find(position: touchPosition) {
            groundImageController.dispatchClick(event: GroundImageEvent(state: groundImage.state, clicked: touchPosition))
            return true
        }
        if let hit = polylineController.findWithClosestPoint(position: touchPosition) {
            polylineController.dispatchClick(event: PolylineEvent(state: hit.entity.state, clicked: hit.closestPoint))
            return true
        }
        if let polygon = polygonController.find(position: touchPosition) {
            polygonController.dispatchClick(event: PolygonEvent(state: polygon.state, clicked: touchPosition))
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
        markerController.handleDragStart(screenPoint: screenPoint)
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
    @MainActor
    private func toScreenPoint(from geoPoint: GeoPoint) -> CGPoint? {
        guard let proxy = typedHolder.mapView.proxy?.proxy,
              let point = proxy.screenPoint(fromLocation: geoPoint.toArcGISPoint()) else {
            return nil
        }
        return point.screenPoint
    }
}
