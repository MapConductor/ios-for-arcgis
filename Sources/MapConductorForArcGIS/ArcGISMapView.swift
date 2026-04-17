import ArcGIS
import Combine
import Foundation
import MapConductorCore
import SwiftUI

public struct ArcGISMapView: View {
    @ObservedObject private var state: ArcGISMapViewState

    private let onMapLoaded: OnMapLoadedHandler<ArcGISMapViewState>?
    private let onMapClick: OnMapEventHandler?
    private let onCameraMoveStart: OnCameraMoveHandler?
    private let onCameraMove: OnCameraMoveHandler?
    private let onCameraMoveEnd: OnCameraMoveHandler?
    private let sdkInitialize: (() -> Void)?
    private let content: () -> MapViewContent

    public init(
        state: ArcGISMapViewState,
        onMapLoaded: OnMapLoadedHandler<ArcGISMapViewState>? = nil,
        onMapClick: OnMapEventHandler? = nil,
        onCameraMoveStart: OnCameraMoveHandler? = nil,
        onCameraMove: OnCameraMoveHandler? = nil,
        onCameraMoveEnd: OnCameraMoveHandler? = nil,
        sdkInitialize: (() -> Void)? = nil,
        @MapViewContentBuilder content: @escaping () -> MapViewContent = { MapViewContent() }
    ) {
        self.state = state
        self.onMapLoaded = onMapLoaded
        self.onMapClick = onMapClick
        self.onCameraMoveStart = onCameraMoveStart
        self.onCameraMove = onCameraMove
        self.onCameraMoveEnd = onCameraMoveEnd
        self.sdkInitialize = sdkInitialize
        self.content = content
    }

    public var body: some View {
        let mapContent = content()
        ArcGISMapViewBody(
            state: state,
            onMapLoaded: onMapLoaded,
            onMapClick: onMapClick,
            onCameraMoveStart: onCameraMoveStart,
            onCameraMove: onCameraMove,
            onCameraMoveEnd: onCameraMoveEnd,
            sdkInitialize: sdkInitialize,
            content: mapContent
        )
    }
}

private struct ArcGISMapViewBody: View {
    @ObservedObject var state: ArcGISMapViewState

    let onMapLoaded: OnMapLoadedHandler<ArcGISMapViewState>?
    let onMapClick: OnMapEventHandler?
    let onCameraMoveStart: OnCameraMoveHandler?
    let onCameraMove: OnCameraMoveHandler?
    let onCameraMoveEnd: OnCameraMoveHandler?
    let sdkInitialize: (() -> Void)?
    let content: MapViewContent

    @StateObject private var model: ArcGISMapViewModel

    init(
        state: ArcGISMapViewState,
        onMapLoaded: OnMapLoadedHandler<ArcGISMapViewState>?,
        onMapClick: OnMapEventHandler?,
        onCameraMoveStart: OnCameraMoveHandler?,
        onCameraMove: OnCameraMoveHandler?,
        onCameraMoveEnd: OnCameraMoveHandler?,
        sdkInitialize: (() -> Void)?,
        content: MapViewContent
    ) {
        self.state = state
        self.onMapLoaded = onMapLoaded
        self.onMapClick = onMapClick
        self.onCameraMoveStart = onCameraMoveStart
        self.onCameraMove = onCameraMove
        self.onCameraMoveEnd = onCameraMoveEnd
        self.sdkInitialize = sdkInitialize
        self.content = content
        ArcGISSdkInitialization.runOnce(sdkInitialize)
        _model = StateObject(wrappedValue: ArcGISMapViewModel(state: state))
    }

    var body: some View {
        ZStack {
            SceneViewReader { proxy in
                SceneView(scene: model.container.scene, graphicsOverlays: model.container.graphicsOverlays)
                    .onSingleTapGesture { screenPoint, mapPoint in
                        Task {
                            _ = await model.controller?.handleTap(screenPoint: screenPoint, mapPoint: mapPoint)
                        }
                    }
                    .onDrawStatusChanged { status in
                        NSLog("[MapConductor][ArcGIS] drawStatus=%@", String(describing: status))
                    }
                    .onAppear {
                        NSLog("[MapConductor][ArcGIS] SceneView onAppear begin")
                        model.attach(proxy: proxy)
                        NSLog("[MapConductor][ArcGIS] proxy attached")
                        model.bind(
                            state: state,
                            onMapClick: onMapClick,
                            onCameraMoveStart: onCameraMoveStart,
                            onCameraMove: onCameraMove,
                            onCameraMoveEnd: onCameraMoveEnd
                        )
                        NSLog("[MapConductor][ArcGIS] model bound")
                        onMapLoaded?(state)
                        NSLog("[MapConductor][ArcGIS] SceneView onAppear end")
                    }
                    .onDisappear {
                        NSLog("[MapConductor][ArcGIS] SceneView onDisappear")
                        model.unbind(state: state)
                    }
                    .task(id: content.identityFingerprint) {
                        NSLog(
                            "[MapConductor][ArcGIS] content task fingerprint=%d markers=%d polylines=%d polygons=%d circles=%d groundImages=%d rasterLayers=%d",
                            content.identityFingerprint,
                            content.markers.count,
                            content.polylines.count,
                            content.polygons.count,
                            content.circles.count,
                            content.groundImages.count,
                            content.rasterLayers.count
                        )
                        await model.updateContent(content)
                    }
                    .task {
                        await model.observeSceneLoadStatus()
                    }
            }

            ForEach(0..<content.views.count, id: \.self) { index in
                content.views[index]
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
private enum ArcGISSdkInitialization {
    private static var didInitialize = false

    static func runOnce(_ sdkInitialize: (() -> Void)?) {
        guard let sdkInitialize else {
            NSLog("[MapConductor][ArcGIS] sdkInitialize is nil before scene creation")
            return
        }
        guard !didInitialize else {
            NSLog("[MapConductor][ArcGIS] sdkInitialize skipped before scene creation because it already ran")
            return
        }
        NSLog("[MapConductor][ArcGIS] sdkInitialize begin before scene creation")
        sdkInitialize()
        didInitialize = true
        NSLog("[MapConductor][ArcGIS] sdkInitialize end before scene creation")
    }
}

@MainActor
private final class ArcGISMapViewModel: ObservableObject {
    let container: ArcGISSceneContainer
    private let markerLayer = GraphicsOverlay()
    private let polylineLayer = GraphicsOverlay()
    private let polygonLayer = GraphicsOverlay()
    private let circleLayer = GraphicsOverlay()

    private(set) var controller: ArcGISMapViewController?
    private var didBind = false

    init(state: ArcGISMapViewState) {
        NSLog(
            "[MapConductor][ArcGIS] ArcGISMapViewModel init design=%@ camera=(lat=%f lon=%f zoom=%f bearing=%f tilt=%f)",
            String(describing: state.mapDesignType),
            state.cameraPosition.position.latitude,
            state.cameraPosition.position.longitude,
            state.cameraPosition.zoom,
            state.cameraPosition.bearing,
            state.cameraPosition.tilt
        )
        let scene = ArcGIS.Scene(basemapStyle: ArcGISDesign.toBasemapStyle(state.mapDesignType))
        let initialCamera = state.cameraPosition.toArcGISCamera()
        let initialCenter = state.cameraPosition.position.toArcGISPoint(spatialReference: .wgs84)
        let initialScale = max(1, state.cameraPosition.altitudeForArcGIS())
        scene.initialViewpoint = Viewpoint(
            center: initialCenter,
            scale: initialScale,
            camera: initialCamera
        )
        let surface = Surface()
        var elevationSources: [ElevationSource] = []
        for source in state.mapDesignType.elevationSources {
            if let url = URL(string: source) {
                let elevationSource = ArcGISTiledElevationSource(url: url)
                elevationSources.append(elevationSource)
                surface.addElevationSource(elevationSource)
            }
        }
        scene.baseSurface = surface

        markerLayer.sceneProperties.surfacePlacement = .relative
        polylineLayer.sceneProperties.surfacePlacement = .drapedBillboarded
        polygonLayer.sceneProperties.surfacePlacement = .drapedBillboarded
        circleLayer.sceneProperties.surfacePlacement = .drapedFlat

        self.container = ArcGISSceneContainer(
            scene: scene,
            graphicsOverlays: [circleLayer, polygonLayer, polylineLayer, markerLayer],
            cameraPosition: state.cameraPosition,
            baseSurface: surface,
            elevationSources: elevationSources
        )
        NSLog("[MapConductor][ArcGIS] ArcGISMapViewModel init complete overlays=%d", container.graphicsOverlays.count)
    }

    func attach(proxy: SceneViewProxy) {
        container.proxy = SceneViewProxyBox(proxy)
    }

    func observeSceneLoadStatus() async {
        logSceneLoadStatus(container.scene.loadStatus)
        for await status in container.scene.$loadStatus {
            logSceneLoadStatus(status)
        }
    }

    private func logSceneLoadStatus(_ status: LoadStatus) {
        if status == .failed {
            NSLog(
                "[MapConductor][ArcGIS] scene loadStatus=%@ error=%@",
                String(describing: status),
                String(describing: container.scene.loadError)
            )
        } else {
            NSLog("[MapConductor][ArcGIS] scene loadStatus=%@", String(describing: status))
        }
    }

    func bind(
        state: ArcGISMapViewState,
        onMapClick: OnMapEventHandler?,
        onCameraMoveStart: OnCameraMoveHandler?,
        onCameraMove: OnCameraMoveHandler?,
        onCameraMoveEnd: OnCameraMoveHandler?
    ) {
        if didBind {
            NSLog("[MapConductor][ArcGIS] bind skipped because model is already bound")
            return
        }
        NSLog("[MapConductor][ArcGIS] bind begin")
        didBind = true

        let holder = ArcGISMapViewHolder(container: container)
        let raster = ArcGISRasterLayerController(scene: container.scene)
        let controller = ArcGISMapViewController(
            holder: holder,
            markerController: ArcGISMarkerController(markerLayer: markerLayer),
            polylineController: ArcGISPolylineOverlayController(polylineLayer: polylineLayer),
            polygonController: ArcGISPolygonOverlayController(polygonLayer: polygonLayer),
            circleController: ArcGISCircleOverlayController(circleLayer: circleLayer),
            groundImageController: ArcGISGroundImageController(scene: container.scene),
            rasterLayerController: raster
        )
        self.controller = controller
        state.setController(controller)
        state.setMapViewHolder(controller.holder)
        controller.setMapClickListener(listener: onMapClick)
        controller.setCameraMoveStartListener(listener: onCameraMoveStart)
        controller.setCameraMoveListener(listener: onCameraMove)
        controller.setCameraMoveEndListener(listener: onCameraMoveEnd)
        NSLog("[MapConductor][ArcGIS] bind end")
    }

    func unbind(state: ArcGISMapViewState) {
        NSLog("[MapConductor][ArcGIS] unbind begin")
        state.setController(nil)
        state.setMapViewHolder(nil)
        controller = nil
        didBind = false
        NSLog("[MapConductor][ArcGIS] unbind end")
    }

    func updateContent(_ content: MapViewContent) async {
        guard let controller else {
            NSLog("[MapConductor][ArcGIS] updateContent skipped because controller is nil")
            return
        }
        NSLog("[MapConductor][ArcGIS] updateContent begin")
        await controller.markerController.syncMarkers(content.markers)
        NSLog("[MapConductor][ArcGIS] markers synced count=%d", content.markers.count)
        await controller.groundImageController.syncGroundImages(content.groundImages)
        NSLog("[MapConductor][ArcGIS] groundImages synced count=%d", content.groundImages.count)
        await controller.rasterLayerController.syncRasterLayers(content.rasterLayers)
        NSLog("[MapConductor][ArcGIS] rasterLayers synced count=%d", content.rasterLayers.count)
        await controller.circleController.syncCircles(content.circles)
        NSLog("[MapConductor][ArcGIS] circles synced count=%d", content.circles.count)
        await controller.polylineController.syncPolylines(content.polylines)
        NSLog("[MapConductor][ArcGIS] polylines synced count=%d", content.polylines.count)
        await controller.polygonController.syncPolygons(content.polygons)
        NSLog("[MapConductor][ArcGIS] polygons synced count=%d", content.polygons.count)
        NSLog("[MapConductor][ArcGIS] updateContent end")
    }
}
