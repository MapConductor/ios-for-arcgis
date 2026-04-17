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

    func moveCamera(position: MapCameraPosition) {
        typedHolder.mapView.lastCameraPosition = position
        Task {
            typedHolder.mapView.proxy?.proxy.setViewpointCamera(position.toArcGISCamera())
        }
    }

    func animateCamera(position: MapCameraPosition, duration: Long) {
        typedHolder.mapView.lastCameraPosition = position
        Task {
            cameraMoveStartListener?(position)
            await typedHolder.mapView.proxy?.proxy.setViewpointCamera(
                position.toArcGISCamera(),
                duration: Double(duration) / 1000
            )
            cameraMoveEndListener?(position)
        }
    }

    func setMapDesignType(_ value: ArcGISMapDesignType) {
        typedHolder.map.basemap = Basemap(style: ArcGISDesign.toBasemapStyle(value))
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

    func handleTap(screenPoint: CGPoint, mapPoint: Point?) async -> Bool {
        let touchPosition = mapPoint?.toGeoPoint()

        if let result = try? await typedHolder.mapView.proxy?.proxy.identify(
            on: markerController.renderer.markerLayer,
            screenPoint: screenPoint,
           tolerance: 12,
           maximumResults: 1
        ),
           let graphic = result.graphics.first,
           let markerId = graphic.attributeValue(forKey: "id") as? String,
           let entity = markerController.markerManager.getEntity(markerId) {
            markerController.dispatchClick(state: entity.state)
            return true
        }

        guard let touchPosition else { return false }

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
}
