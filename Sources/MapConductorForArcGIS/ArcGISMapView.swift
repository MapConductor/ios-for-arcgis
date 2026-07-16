import ArcGIS
import Combine
import Foundation
import MapConductorCore
import SwiftUI

private typealias ArcGISStrategyController = StrategyMarkerController<
    Graphic,
    AnyMarkerRenderingStrategy<Graphic>,
    ArcGISMarkerRenderer
>

public struct ArcGISMapView: View {
    @ObservedObject private var state: ArcGISMapViewState

    private let onMapLoaded: OnMapLoadedHandler<ArcGISMapViewState>?
    private let onMapClick: OnMapEventHandler?
    private let onMapLongClick: OnMapEventHandler?
    private let onCameraMoveStart: OnCameraMoveHandler?
    private let onCameraMove: OnCameraMoveHandler?
    private let onCameraMoveEnd: OnCameraMoveHandler?
    private let sdkInitialize: (() -> Void)?
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
        self.onMapLoaded = onMapLoaded
        self.onMapClick = onMapClick
        self.onMapLongClick = onMapLongClick
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
            onMapLongClick: onMapLongClick,
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
    let onMapLongClick: OnMapEventHandler?
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
        onMapLongClick: OnMapEventHandler?,
        onCameraMoveStart: OnCameraMoveHandler?,
        onCameraMove: OnCameraMoveHandler?,
        onCameraMoveEnd: OnCameraMoveHandler?,
        sdkInitialize: (() -> Void)?,
        content: MapViewContent
    ) {
        self.state = state
        self.onMapLoaded = onMapLoaded
        self.onMapClick = onMapClick
        self.onMapLongClick = onMapLongClick
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
                    .onDrawStatusChanged { status in
                        NSLog("[MapConductor][ArcGIS] drawStatus=%@", String(describing: status))
                    }
                    .onCameraChanged { camera in
                        model.notifyCameraMove(camera: camera)
                    }
                    .onViewpointChanged(kind: .centerAndScale) { _ in
                        model.updateInfoBubbleLayouts()
                    }
                    .onNavigatingChanged { _ in
                        model.updateInfoBubbleLayouts()
                    }
                    .onInteractingChanged { isInteracting in
                        if !isInteracting {
                            model.handleDragInteractionEnded()
                        }
                    }
                    .onAppear {
                        NSLog("[MapConductor][ArcGIS] SceneView onAppear begin")
                        model.attach(proxy: proxy)
                        NSLog("[MapConductor][ArcGIS] proxy attached")
                        model.bind(
                            state: state,
                            onMapClick: onMapClick,
                            onMapLongClick: onMapLongClick,
                            onCameraMoveStart: onCameraMoveStart,
                            onCameraMove: onCameraMove,
                            onCameraMoveEnd: onCameraMoveEnd
                        )
                        NSLog("[MapConductor][ArcGIS] model bound")
                        model.controller?.notifyMapInitialized()
                        onMapLoaded?(state)
                        NSLog("[MapConductor][ArcGIS] SceneView onAppear end")
                    }
                    .onDisappear {
                        NSLog("[MapConductor][ArcGIS] SceneView onDisappear")
                        model.unbind(state: state)
                    }
                    .task(id: content.identityFingerprint) {
                        NSLog(
                            "[MapConductor][ArcGIS] content task fingerprint=%d markers=%d polylines=%d polygons=%d circles=%d groundImages=%d rasterLayers=%d infoBubbles=%d",
                            content.identityFingerprint,
                            content.markers.count,
                            content.polylines.count,
                            content.polygons.count,
                            content.circles.count,
                            content.groundImages.count,
                            content.rasterLayers.count,
                            content.infoBubbles.count
                        )
                        await model.updateContent(content)
                    }
                    .task {
                        await model.observeSceneLoadStatus()
                    }
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { model.updateViewportSize($0) }
            }

            InfoBubbleContainerRepresentable(container: model.infoBubbleContainer)

            ForEach(0..<content.views.count, id: \.self) { index in
                content.views[index]
            }

            if !state.uiSettings.scrollGesture {
                Color.clear
                    .contentShape(Rectangle())
                    .highPriorityGesture(DragGesture())
            }
        }
    }
}

private extension MapViewContent {
    var identityFingerprint: Int {
        var hasher = Hasher()
        markers.forEach {
            hasher.combine($0.id)
            hasher.combine($0.state.position.latitude)
            hasher.combine($0.state.position.longitude)
        }
        markerRenderingMarkers.forEach {
            hasher.combine($0.id)
            hasher.combine($0.position.latitude)
            hasher.combine($0.position.longitude)
        }
        if markerRenderingStrategy != nil { hasher.combine(true) }
        polylines.forEach { hasher.combine($0.id) }
        polygons.forEach { hasher.combine($0.id) }
        circles.forEach { hasher.combine($0.id) }
        groundImages.forEach { hasher.combine($0.id) }
        rasterLayers.forEach { hasher.combine($0.id) }
        infoBubbles.forEach { hasher.combine($0.id) }
        return hasher.finalize()
    }
}

private struct InfoBubbleContainerRepresentable: UIViewRepresentable {
    let container: PassthroughContainerView

    func makeUIView(context: Context) -> PassthroughContainerView { container }
    func updateUIView(_ uiView: PassthroughContainerView, context: Context) {}
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
    private let hullPolygonLayer = GraphicsOverlay()
    private let circleLayer = GraphicsOverlay()

    private(set) var controller: ArcGISMapViewController?
    private var hullPolygonController: ArcGISPolygonOverlayController?
    private var didBind = false
    private var dragState: MarkerDragState = .idle

    private var cameraMoveEndWorkItem: DispatchWorkItem?
    private let cameraMoveEndDebounceSeconds = 0.18

    private var currentMarkerTileRasterLayer: RasterLayerState?

    private var strategyMarkerController: ArcGISStrategyController?
    private var strategyMarkerRenderer: ArcGISMarkerRenderer?
    private var strategyMarkerSubscriptions: [String: AnyCancellable] = [:]
    private var strategyMarkerStatesById: [String: MarkerState] = [:]

    let infoBubbleContainer = PassthroughContainerView()
    private var infoBubbleCoordinator: InfoBubbleOverlayCoordinator?

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

        markerLayer.renderingMode = .dynamic
        markerLayer.sceneProperties.surfacePlacement = .relative
        polylineLayer.sceneProperties.surfacePlacement = .drapedBillboarded
        polygonLayer.sceneProperties.surfacePlacement = .drapedBillboarded
        hullPolygonLayer.sceneProperties.surfacePlacement = .drapedBillboarded
        circleLayer.sceneProperties.surfacePlacement = .drapedFlat

        self.container = ArcGISSceneContainer(
            scene: scene,
            graphicsOverlays: [circleLayer, polygonLayer, hullPolygonLayer, polylineLayer, markerLayer],
            cameraPosition: state.cameraPosition,
            baseSurface: surface,
            elevationSources: elevationSources
        )
        NSLog("[MapConductor][ArcGIS] ArcGISMapViewModel init complete overlays=%d", container.graphicsOverlays.count)
    }

    func attach(proxy: SceneViewProxy) {
        container.proxy = SceneViewProxyBox(proxy)
    }

    func updateViewportSize(_ size: CGSize) {
        container.viewportSize = size
        guard didBind, container.proxy != nil else { return }
        container.proxy?.proxy.setViewpointCamera(
            container.lastCameraPosition.toArcGISCamera(viewportSize: size)
        )
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
        onMapLongClick: OnMapEventHandler?,
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
        self.hullPolygonController = ArcGISPolygonOverlayController(
            polygonLayer: hullPolygonLayer,
            scene: container.scene
        )
        let controller = ArcGISMapViewController(
            holder: holder,
            markerController: ArcGISMarkerController(
                markerLayer: markerLayer,
                container: container,
                onUpdateInfoBubble: { [weak self] id in
                    self?.infoBubbleCoordinator?.updateInfoBubblePosition(for: id)
                }
            ),
            polylineController: ArcGISPolylineOverlayController(polylineLayer: polylineLayer),
            polygonController: ArcGISPolygonOverlayController(polygonLayer: polygonLayer, scene: container.scene),
            circleController: ArcGISCircleOverlayController(circleLayer: circleLayer),
            groundImageController: ArcGISGroundImageController(scene: container.scene),
            rasterLayerController: raster,
        )
        self.controller = controller
        state.setController(controller)
        state.setMapViewHolder(controller.holder)
        controller.setMapClickListener(listener: onMapClick)
        controller.setMapLongClickListener(listener: onMapLongClick)
        controller.setCameraMoveStartListener(listener: onCameraMoveStart)
        controller.setCameraMoveListener(listener: onCameraMove)
        controller.setCameraMoveEndListener(listener: onCameraMoveEnd)
        controller.setMapDesignTypeChangeListener(listener: { [weak state] value in state?.onMapDesignTypeChange(value: value) })

        let markerController = controller.markerController
        markerController.markerTileRasterLayerCallback = { [weak self] state in
            self?.currentMarkerTileRasterLayer = state
        }

        infoBubbleCoordinator = InfoBubbleOverlayCoordinator(
            container: infoBubbleContainer,
            project: { [weak self] point in
                guard let proxy = self?.container.proxy?.proxy else { return nil }
                return proxy.screenPoint(fromLocation: point.toArcGISPoint(spatialReference: .wgs84))?.screenPoint
            },
            resolveMarkerStateForIcon: { [weak markerController] id, bubbleMarker in
                markerController?.markerManager.getEntity(id)?.state ?? bubbleMarker
            },
            iconMetrics: { markerState in
                let icon = (markerState.icon ?? DefaultMarkerIcon()).toBitmapIcon()
                return MarkerIconMetrics(size: icon.size, anchor: icon.anchor, infoAnchor: icon.infoAnchor)
            }
        )

        // Screen-space marker animation layer: shares the info-bubble
        // container (inserted below the bubbles) and the same projection.
        markerController.renderer.animationOverlay = MarkerAnimationOverlayCoordinator(
            container: infoBubbleContainer,
            project: { [weak self] point in
                guard let proxy = self?.container.proxy?.proxy else { return nil }
                return proxy.screenPoint(fromLocation: point.toArcGISPoint(spatialReference: .wgs84))?.screenPoint
            }
        )
        NSLog("[MapConductor][ArcGIS] bind end")
    }

    func unbind(state: ArcGISMapViewState) {
        NSLog("[MapConductor][ArcGIS] unbind begin")
        dragState = .idle
        controller?.markerController.renderer.animationOverlay?.unbind()
        controller?.markerController.renderer.animationOverlay = nil
        state.setController(nil as ArcGISMapViewController?)
        state.setMapViewHolder(nil)
        controller = nil
        strategyMarkerSubscriptions.values.forEach { $0.cancel() }
        strategyMarkerSubscriptions.removeAll()
        strategyMarkerStatesById.removeAll()
        strategyMarkerRenderer?.unbind()
        strategyMarkerRenderer = nil
        strategyMarkerController?.destroy()
        strategyMarkerController = nil
        hullPolygonController = nil
        infoBubbleCoordinator?.unbind()
        infoBubbleCoordinator = nil
        didBind = false
        NSLog("[MapConductor][ArcGIS] unbind end")
    }

    func handleDragShouldBegin(screenPoint: CGPoint, mapPoint: Point?) async -> Bool {
        guard let controller else { return false }
        let didStart = await controller.handleMarkerDragStart(screenPoint: screenPoint, mapPoint: mapPoint)
        dragState = didStart ? .dragging : .idle
        return didStart
    }

    func handleDragChanged(screenPoint: CGPoint, mapPoint: Point?) {
        guard let controller else { return }
        switch dragState {
        case .dragging:
            if let mapPoint {
                _ = controller.handleMarkerDrag(mapPoint: mapPoint)
            } else {
                Task { [weak controller] in
                    _ = await controller?.handleMarkerDrag(screenPoint: screenPoint)
                }
            }
        case .idle:
            break
        }
    }

    func handleDragEnded(screenPoint: CGPoint, mapPoint: Point?) {
        guard let controller else {
            dragState = .idle
            return
        }

        switch dragState {
        case .dragging:
            if let mapPoint {
                _ = controller.handleMarkerDragEnd(mapPoint: mapPoint)
            } else {
                Task { [weak controller] in
                    _ = await controller?.handleMarkerDragEnd(screenPoint: screenPoint)
                }
            }
        case .idle:
            break
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

    func notifyCameraMove(camera: Camera) {
        let position = camera.toMapCameraPosition(
            logicalTiltHint: controller?.lastLogicalTilt,
            viewportSize: container.viewportSize
        )
        container.lastCameraPosition = position
        controller?.notifyCameraMove(position)

        cameraMoveEndWorkItem?.cancel()
        let viewportSize = container.viewportSize
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let vr = Self.computeVisibleRegion(for: position, viewportSize: viewportSize)
            let posWithVR = MapCameraPosition(
                position: position.position,
                zoom: position.zoom,
                bearing: position.bearing,
                tilt: position.tilt,
                paddings: position.paddings,
                visibleRegion: vr
            )
            self.controller?.notifyCameraMoveEnd(posWithVR)
            Task { [weak self] in
                await self?.strategyMarkerController?.onCameraChanged(mapCameraPosition: posWithVR)
            }
        }
        cameraMoveEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + cameraMoveEndDebounceSeconds, execute: workItem)
    }

    private static func computeVisibleRegion(for position: MapCameraPosition, viewportSize: CGSize?) -> VisibleRegion? {
        guard let size = viewportSize, size.width > 0, size.height > 0 else { return nil }

        let center = GeoPoint.from(position: position.position)
        let latRad = center.latitude * .pi / 180
        // bearing θ: screen-up direction corresponds to geographic bearing θ
        let θ = position.bearing * .pi / 180

        // Web-Mercator ground resolution: metres per pixel at this zoom and latitude
        let metersPerPixel = (2 * .pi * 6_371_000.0 * cos(latRad)) / (256.0 * pow(2.0, position.zoom))

        let halfW = Double(size.width) / 2
        let halfH = Double(size.height) / 2

        // Convert screen offset (sx right, sy down) → geographic offset (east, north in metres)
        // geo_east  =  (sx·cos θ − sy·sin θ) · m/px
        // geo_north = (−sx·sin θ − sy·cos θ) · m/px
        func cornerGeo(sxPx: Double, syPx: Double) -> GeoPoint {
            let eastM  = ( sxPx * cos(θ) - syPx * sin(θ)) * metersPerPixel
            let northM = (-sxPx * sin(θ) - syPx * cos(θ)) * metersPerPixel
            let dLat = northM / 111_000.0
            let dLng = eastM  / (111_000.0 * cos(latRad))
            return GeoPoint(latitude: center.latitude + dLat, longitude: center.longitude + dLng)
        }

        // Screen corners: sx = signed x from centre, sy = signed y from centre (down positive)
        let nl = cornerGeo(sxPx: -halfW, syPx: +halfH)  // bottom-left  → nearLeft
        let nr = cornerGeo(sxPx: +halfW, syPx: +halfH)  // bottom-right → nearRight
        let fl = cornerGeo(sxPx: -halfW, syPx: -halfH)  // top-left     → farLeft
        let fr = cornerGeo(sxPx: +halfW, syPx: -halfH)  // top-right    → farRight

        let bounds = GeoRectBounds()
        [nl, nr, fl, fr].forEach { bounds.extend(point: $0) }

        return VisibleRegion(bounds: bounds, nearLeft: nl, nearRight: nr, farLeft: fl, farRight: fr)
    }

    func syncInfoBubbles(_ bubbles: [InfoBubble]) {
        infoBubbleCoordinator?.syncInfoBubbles(bubbles)
    }

    func updateInfoBubbleLayouts() {
        infoBubbleCoordinator?.updateAllLayouts()
    }

    private func updateStrategyRendering(_ content: MapViewContent) {
        if let strategy = content.markerRenderingStrategy as? AnyMarkerRenderingStrategy<Graphic> {
            if strategyMarkerController == nil ||
                strategyMarkerController?.markerManager !== strategy.markerManager {
                strategyMarkerRenderer?.unbind()
                let renderer = ArcGISMarkerRenderer(markerLayer: markerLayer, container: container)
                strategyMarkerRenderer = renderer
                strategyMarkerController = ArcGISStrategyController(strategy: strategy, renderer: renderer)
                Task { [weak self] in
                    guard let self else { return }
                    let pos = self.container.lastCameraPosition
                    let vr = Self.computeVisibleRegion(for: pos, viewportSize: self.container.viewportSize)
                    let posWithVR = MapCameraPosition(
                        position: pos.position,
                        zoom: pos.zoom,
                        bearing: pos.bearing,
                        tilt: pos.tilt,
                        paddings: pos.paddings,
                        visibleRegion: vr
                    )
                    await self.strategyMarkerController?.onCameraChanged(mapCameraPosition: posWithVR)
                }
            }
            syncStrategyMarkers(content.markerRenderingMarkers)
        } else {
            strategyMarkerSubscriptions.values.forEach { $0.cancel() }
            strategyMarkerSubscriptions.removeAll()
            strategyMarkerStatesById.removeAll()
            strategyMarkerRenderer?.unbind()
            strategyMarkerRenderer = nil
            strategyMarkerController?.destroy()
            strategyMarkerController = nil
        }
    }

    private func syncStrategyMarkers(_ markers: [MarkerState]) {
        guard let controller = strategyMarkerController else { return }
        let newIds = Set(markers.map { $0.id })
        let oldIds = Set(strategyMarkerStatesById.keys)
        var shouldSyncList = newIds != oldIds

        var newStatesById: [String: MarkerState] = [:]
        for state in markers {
            if let existing = strategyMarkerStatesById[state.id], existing !== state {
                strategyMarkerSubscriptions[state.id]?.cancel()
                strategyMarkerSubscriptions.removeValue(forKey: state.id)
                shouldSyncList = true
            }
            newStatesById[state.id] = state
        }
        strategyMarkerStatesById = newStatesById

        let removedIds = oldIds.subtracting(newIds)
        for id in removedIds {
            strategyMarkerSubscriptions[id]?.cancel()
            strategyMarkerSubscriptions.removeValue(forKey: id)
        }

        if shouldSyncList {
            Task { [weak self] in
                guard let self else { return }
                await controller.add(data: markers)
            }
        }
        for state in markers { subscribeToStrategyMarker(state) }
    }

    private func subscribeToStrategyMarker(_ state: MarkerState) {
        guard strategyMarkerSubscriptions[state.id] == nil else { return }
        strategyMarkerSubscriptions[state.id] = state.asFlow()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.strategyMarkerStatesById[state.id] != nil else { return }
                Task { [weak self] in
                    await self?.strategyMarkerController?.update(state: state)
                }
            }
    }

    func updateContent(_ content: MapViewContent) async {
        guard let controller else {
            NSLog("[MapConductor][ArcGIS] updateContent skipped because controller is nil")
            return
        }
        NSLog("[MapConductor][ArcGIS] updateContent begin")
        controller.markerController.tilingOptions = content.markerTilingOptions
        if content.markerRenderingStrategy != nil {
            await controller.markerController.syncMarkers([])
            updateStrategyRendering(content)
        } else {
            updateStrategyRendering(content)
            await controller.markerController.syncMarkers(content.markers)
        }
        NSLog("[MapConductor][ArcGIS] markers synced count=%d strategyMarkers=%d", content.markers.count, content.markerRenderingMarkers.count)
        await controller.groundImageController.syncGroundImages(content.groundImages)
        NSLog("[MapConductor][ArcGIS] groundImages synced count=%d", content.groundImages.count)
        let tileLayer = currentMarkerTileRasterLayer.map { RasterLayer(state: $0) }
        let allRasterLayers = content.rasterLayers + (tileLayer.map { [$0] } ?? [])
        await controller.rasterLayerController.syncRasterLayers(allRasterLayers)
        NSLog("[MapConductor][ArcGIS] rasterLayers synced count=%d (markerTile=%d)", allRasterLayers.count, tileLayer != nil ? 1 : 0)
        await controller.circleController.syncCircles(content.circles)
        NSLog("[MapConductor][ArcGIS] circles synced count=%d", content.circles.count)
        await controller.polylineController.syncPolylines(content.polylines)
        NSLog("[MapConductor][ArcGIS] polylines synced count=%d", content.polylines.count)
        await controller.polygonController.syncPolygons(content.polygons)
        for handler in content.polygonSyncHandlers {
            let hullController = hullPolygonController
            handler.bindPolygonSync { [weak hullController] states in
                await hullController?.add(data: states)
            }
        }
        NSLog("[MapConductor][ArcGIS] polygons synced count=%d", content.polygons.count)
        syncInfoBubbles(content.infoBubbles)
        NSLog("[MapConductor][ArcGIS] infoBubbles synced count=%d", content.infoBubbles.count)
        NSLog("[MapConductor][ArcGIS] updateContent end")
    }
}

private enum MarkerDragState {
    case idle
    case dragging
}
