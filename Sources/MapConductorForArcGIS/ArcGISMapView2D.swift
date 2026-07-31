import ArcGIS
import Combine
import Foundation
import MapConductorCore
import SwiftUI

public struct ArcGISMapView2D: View {
    @ObservedObject private var state: ArcGISMapViewState
    private let handlers: MapViewHandlers<ArcGISMapViewState>
    private let content: () -> MapViewContent

    public init(
        state: ArcGISMapViewState,
        onMapLoaded: OnMapLoadedHandler<ArcGISMapViewState>? = nil,
        onMapClick: OnMapEventHandler? = nil,
        onMapLongClick: OnMapEventHandler? = nil,
        onCameraMoveStart: OnCameraMoveHandler? = nil,
        onCameraMove: OnCameraMoveHandler? = nil,
        onCameraMoveEnd: OnCameraMoveHandler? = nil,
        sdkInitialize: (() -> Void)? = nil,
        @MapViewContentBuilder content: @escaping () -> MapViewContent = { MapViewContent() }
    ) {
        self.state = state
        self.handlers = MapViewHandlers(
            onMapLoaded: onMapLoaded,
            onMapClick: onMapClick,
            onMapLongClick: onMapLongClick,
            onCameraMoveStart: onCameraMoveStart,
            onCameraMove: onCameraMove,
            onCameraMoveEnd: onCameraMoveEnd,
            sdkInitialize: sdkInitialize
        )
        self.content = content
        ArcGISSdkInitialization2D.runOnce(sdkInitialize)
    }

    public var body: some View {
        let mapContent = content()
        ArcGISMapView2DBody(
            state: state,
            handlers: handlers,
            content: mapContent
        )
    }
}

private struct ArcGISMapView2DBody: View {
    @ObservedObject var state: ArcGISMapViewState

    let handlers: MapViewHandlers<ArcGISMapViewState>
    let content: MapViewContent

    @StateObject private var model: ArcGISMapView2DModel

    init(
        state: ArcGISMapViewState,
        handlers: MapViewHandlers<ArcGISMapViewState>,
        content: MapViewContent
    ) {
        self.state = state
        self.handlers = handlers
        self.content = content
        _model = StateObject(wrappedValue: ArcGISMapView2DModel(state: state))
    }

    var body: some View {
        MapViewBase(
            attributionRules: state.mapDesignType.attributionRules,
            camera: state.cameraPosition,
            content: content
        ) {
            MapViewReader { proxy in
                MapView(
                map: model.container.map,
                graphicsOverlays: model.container.graphicsOverlays
            )
            .onSingleTapGesture { screenPoint, mapPoint in
                Task {
                    _ = await model.controller?.handleTap(screenPoint: screenPoint, mapPoint: mapPoint)
                }
            }
            .onLongPressGesture { screenPoint, mapPoint in
                Task {
                    await model.controller?.handleLongPress(screenPoint: screenPoint, mapPoint: mapPoint)
                }
            }
            .onDragGesture(
                shouldBegin: { screenPoint, mapPoint in
                    await model.handleDragShouldBegin(screenPoint: screenPoint, mapPoint: mapPoint)
                },
                onChanged: { screenPoint, mapPoint in
                    model.handleDragChanged(screenPoint: screenPoint, mapPoint: mapPoint)
                },
                onEnded: { screenPoint, mapPoint in
                    model.handleDragEnded(screenPoint: screenPoint, mapPoint: mapPoint)
                },
                onCancelled: {
                    model.handleDragCancelled()
                }
            )
            .onViewpointChanged(kind: .centerAndScale) { viewpoint in
                model.updateViewpoint(viewpoint)
            }
            .onInteractingChanged { isInteracting in
                if !isInteracting {
                    model.handleDragInteractionEnded()
                }
            }
            .onAppear {
                model.attach(proxy: proxy)
                model.bind(
                    state: state,
                    onMapClick: handlers.onMapClick,
                    onMapLongClick: handlers.onMapLongClick,
                    onCameraMoveStart: handlers.onCameraMoveStart,
                    onCameraMove: handlers.onCameraMove,
                    onCameraMoveEnd: handlers.onCameraMoveEnd
                )
                model.controller?.notifyMapInitialized()
                handlers.onMapLoaded?(state)
            }
            .onDisappear {
                model.unbind(state: state)
            }
            .task(id: content.identityFingerprint) {
                await model.updateContent(content)
            }
            }
        }
    }
}

private extension MapViewContent {
    var identityFingerprint: Int {
        var hasher = Hasher()
        markers.forEach { hasher.combine($0.id) }
        polylines.forEach { hasher.combine($0.id) }
        polygons.forEach { hasher.combine($0.id) }
        circles.forEach { hasher.combine($0.id) }
        groundImages.forEach { hasher.combine($0.id) }
        rasterLayers.forEach { hasher.combine($0.id) }
        return hasher.finalize()
    }
}

@MainActor
private final class ArcGISMapView2DModel: ObservableObject {
    let container: ArcGISMapContainer2D
    private let markerLayer = GraphicsOverlay()
    private let polylineLayer = GraphicsOverlay()
    private let polygonLayer = GraphicsOverlay()
    private let hullPolygonLayer = GraphicsOverlay()
    private let circleLayer = GraphicsOverlay()

    private(set) var controller: ArcGISMapView2DController?
    private var hullPolygonController: ArcGISPolygonOverlayController?
    private var overlayScope: MapOverlayScope?
    private var didBind = false
    private var dragState: MarkerDragState2D = .idle

    init(state: ArcGISMapViewState) {
        let map = ArcGIS.Map(basemapStyle: ArcGISDesign.toBasemapStyle(state.mapDesignType))
        let initialCenter = state.cameraPosition.position.toArcGISPoint(spatialReference: .wgs84)
        let initialScale = ArcGISMapView2DController.zoomToScale(
            state.cameraPosition.zoom,
            latitude: state.cameraPosition.position.latitude
        )
        map.initialViewpoint = Viewpoint(center: initialCenter, scale: max(1, initialScale))

        self.container = ArcGISMapContainer2D(
            map: map,
            graphicsOverlays: [circleLayer, polygonLayer, hullPolygonLayer, polylineLayer, markerLayer],
            cameraPosition: state.cameraPosition
        )
    }

    func attach(proxy: MapViewProxy) {
        container.proxy = MapViewProxyBox(proxy)
    }

    func updateViewpoint(_ viewpoint: Viewpoint?) {
        guard let viewpoint,
              let center = viewpoint.targetGeometry as? Point else { return }
        let lat = center.y
        let lon = center.x
        let scale = viewpoint.targetScale
        let zoom = ArcGISMapView2DController.scaleToZoom(scale, latitude: lat)
        let cameraPosition = MapCameraPosition(
            position: GeoPoint(latitude: lat, longitude: lon),
            zoom: zoom,
            bearing: 0,
            tilt: 0,
            paddings: MapPaddings.Zeros
        )
        controller?.notifyCameraMove(cameraPosition)
    }

    func bind(
        state: ArcGISMapViewState,
        onMapClick: OnMapEventHandler?,
        onMapLongClick: OnMapEventHandler?,
        onCameraMoveStart: OnCameraMoveHandler?,
        onCameraMove: OnCameraMoveHandler?,
        onCameraMoveEnd: OnCameraMoveHandler?
    ) {
        guard !didBind else { return }
        didBind = true

        let holder = ArcGISMapView2DHolder(container: container)
        let raster = ArcGISRasterLayerController(map: container.map)
        self.hullPolygonController = ArcGISPolygonOverlayController(
            polygonLayer: hullPolygonLayer
        )
        let controller = ArcGISMapView2DController(
            holder: holder,
            markerController: ArcGISMarkerController(
                markerLayer: markerLayer,
                container: container,
                onUpdateInfoBubble: { _ in }
            ),
            polylineController: ArcGISPolylineOverlayController(polylineLayer: polylineLayer),
            polygonController: ArcGISPolygonOverlayController(polygonLayer: polygonLayer),
            circleController: ArcGISCircleOverlayController(circleLayer: circleLayer),
            groundImageController: ArcGISGroundImageController(scene: nil),
            rasterLayerController: raster
        )
        self.controller = controller

        let overlayScope = MapOverlayScope()
        self.overlayScope = overlayScope
        bindOverlayCollector(overlayScope.circleCollector, to: controller.circleController)
        bindOverlayCollector(overlayScope.polylineCollector, to: controller.polylineController)
        bindOverlayCollector(overlayScope.polygonCollector, to: controller.polygonController)
        bindOverlayCollector(overlayScope.rasterLayerCollector, to: controller.rasterLayerController)
        bindOverlayCollector(overlayScope.groundImageCollector, to: controller.groundImageController)

        state.setController(controller)
        state.setMapView2DHolder(controller.typedHolder)
        controller.setMapClickListener(listener: onMapClick)
        controller.setMapLongClickListener(listener: onMapLongClick)
        controller.setCameraMoveStartListener(listener: onCameraMoveStart)
        controller.setCameraMoveListener(listener: onCameraMove)
        controller.setCameraMoveEndListener(listener: onCameraMoveEnd)
        controller.setMapDesignTypeChangeListener(listener: { [weak state] value in state?.onMapDesignTypeChange(value: value) })
    }

    func unbind(state: ArcGISMapViewState) {
        dragState = .idle
        state.setController(nil as ArcGISMapView2DController?)
        state.setMapView2DHolder(nil)
        controller = nil
        hullPolygonController = nil
        overlayScope?.clear()
        overlayScope = nil
        didBind = false
    }

    func handleDragShouldBegin(screenPoint: CGPoint, mapPoint: Point?) async -> Bool {
        guard let controller else { return false }
        let didStart = await controller.handleMarkerDragStart(screenPoint: screenPoint, mapPoint: mapPoint)
        dragState = didStart ? .dragging : .idle
        return didStart
    }

    func handleDragChanged(screenPoint: CGPoint, mapPoint: Point?) {
        guard let controller, dragState == .dragging else { return }
        if let mapPoint {
            _ = controller.handleMarkerDrag(mapPoint: mapPoint)
        } else {
            Task { [weak controller] in
                _ = await controller?.handleMarkerDrag(screenPoint: screenPoint)
            }
        }
    }

    func handleDragEnded(screenPoint: CGPoint, mapPoint: Point?) {
        guard let controller else {
            dragState = .idle
            return
        }
        if dragState == .dragging {
            if let mapPoint {
                _ = controller.handleMarkerDragEnd(mapPoint: mapPoint)
            } else {
                Task { [weak controller] in
                    _ = await controller?.handleMarkerDragEnd(screenPoint: screenPoint)
                }
            }
        }
        dragState = .idle
    }

    func handleDragCancelled() {
        _ = controller?.cancelMarkerDrag()
        dragState = .idle
    }

    func handleDragInteractionEnded() {
        guard dragState == .dragging else { return }
        _ = controller?.finishMarkerDrag()
        dragState = .idle
    }

    func updateContent(_ content: MapViewContent) async {
        guard let controller else { return }
        await controller.markerController.clear()
        let markers = content.markers.map(\.state)
        await controller.markerController.add(data: markers)
        overlayScope?.polylineCollector.sync(content.polylines.map { $0.state })
        overlayScope?.polygonCollector.sync(content.polygons.map { $0.state })
        for handler in content.polygonSyncHandlers {
            let hullController = hullPolygonController
            handler.bindPolygonSync { [weak hullController] states in
                await hullController?.add(data: states)
            }
        }
        overlayScope?.circleCollector.sync(content.circles.map { $0.state })
        overlayScope?.groundImageCollector.sync(content.groundImages.map { $0.state })
        overlayScope?.rasterLayerCollector.sync(content.rasterLayers.map { $0.state })
    }
}

private enum MarkerDragState2D {
    case idle
    case dragging
}

@MainActor
private enum ArcGISSdkInitialization2D {
    private static var didInitialize = false

    static func runOnce(_ sdkInitialize: (() -> Void)?) {
        guard let sdkInitialize, !didInitialize else { return }
        sdkInitialize()
        didInitialize = true
    }
}
