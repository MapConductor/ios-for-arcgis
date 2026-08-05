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
    private let cameraRestriction: CameraRestriction?
    private let handlers: MapViewHandlers<ArcGISMapViewState>
    private let content: () -> MapViewContent

    public init(
        state: ArcGISMapViewState,
        cameraRestriction: CameraRestriction? = nil,
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
        self.cameraRestriction = cameraRestriction
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
    }

    public var body: some View {
        // The provider's registry is in scope only while content is being assembled —
        // the same window in which Compose provides `LocalMapServiceRegistry` around the
        // content lambda. Bracketing the pass lets a removed plugin be noticed.
        let support = state.serviceRegistry.get(MarkerRenderingSupportKey.self)
        support?.beginContentPass()
        let mapContent = MapServiceRegistryScope.with(state.serviceRegistry) { content() }
        support?.endContentPass()
        return ArcGISMapViewBody(
            state: state,
            cameraRestriction: cameraRestriction,
            handlers: handlers,
            content: mapContent
        )
    }
}

private struct ArcGISMapViewBody: View {
    @ObservedObject var state: ArcGISMapViewState

    let cameraRestriction: CameraRestriction?
    let handlers: MapViewHandlers<ArcGISMapViewState>
    let content: MapViewContent

    @StateObject private var model: ArcGISMapViewModel

    init(
        state: ArcGISMapViewState,
        cameraRestriction: CameraRestriction? = nil,
        handlers: MapViewHandlers<ArcGISMapViewState>,
        content: MapViewContent
    ) {
        self.state = state
        self.cameraRestriction = cameraRestriction
        self.handlers = handlers
        self.content = content
        ArcGISSdkInitialization.runOnce(handlers.sdkInitialize)
        _model = StateObject(wrappedValue: ArcGISMapViewModel(state: state))
    }

    var body: some View {
        MapViewBase(
            attributionRules: state.mapDesignType.attributionRules,
            camera: state.cameraPosition,
            content: content
        ) {
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
                    // マーカードラッグは「1秒長押し → ドラッグ」。ArcGIS の onLongPressGesture /
                    // onDragGesture は排他で長押し後にドラッグが発火しないため、単一の SwiftUI
                    // シーケンスジェスチャを使う（ArcGIS 専用モディファイアの後に置く必要がある）。
                    // highPriorityGesture なので 1 秒ホールド成立時のみ地図パンより優先される
                    // （通常の即時ドラッグはホールド不成立→地図パン、タップ→InfoBubble）。
                    .highPriorityGesture(
                        LongPressGesture(minimumDuration: 1.0)
                            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                            .onChanged { value in
                                if case let .second(true, drag?) = value {
                                    model.handleHoldDrag(location: drag.location, start: drag.startLocation)
                                }
                            }
                            .onEnded { _ in
                                model.handleHoldDragEnd()
                            }
                    )
                    .onAppear {
                        NSLog("[MapConductor][ArcGIS] SceneView onAppear begin")
                        model.attach(proxy: proxy)
                        NSLog("[MapConductor][ArcGIS] proxy attached")
                        model.bind(
                            state: state,
                            cameraRestriction: cameraRestriction,
                            onMapClick: handlers.onMapClick,
                            onMapLongClick: handlers.onMapLongClick,
                            onCameraMoveStart: handlers.onCameraMoveStart,
                            onCameraMove: handlers.onCameraMove,
                            onCameraMoveEnd: handlers.onCameraMoveEnd
                        )
                        NSLog("[MapConductor][ArcGIS] model bound")
                        model.controller?.notifyMapInitialized()
                        handlers.onMapLoaded?(state)
                        NSLog("[MapConductor][ArcGIS] SceneView onAppear end")
                    }
                    .onDisappear {
                        NSLog("[MapConductor][ArcGIS] SceneView onDisappear")
                        model.unbind(state: state)
                    }
                    .task(id: content.identityFingerprint ^ model.strategyFingerprint) {
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
        } topContent: {
            if !state.uiSettings.scrollGesture {
                Color.clear
                    .contentShape(Rectangle())
                    .highPriorityGesture(DragGesture())
            }
        }
        .onAppear { warnUnsupportedSceneGestures(state.uiSettings) }
        .onChange(of: state.uiSettings) { _, ui in warnUnsupportedSceneGestures(ui) }
    }
}

private extension MapViewContent {
    /// 差分検出用のフィンガープリント。strategy 由来のマーカーは `MapViewContent` から
    /// 外れたため、``ArcGISMapViewModel/strategyFingerprint`` を足し合わせて使う。
    var identityFingerprint: Int {
        var hasher = Hasher()
        markers.forEach {
            hasher.combine($0.id)
            hasher.combine($0.state.position.latitude)
            hasher.combine($0.state.position.longitude)
        }
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
private final class ArcGISMapViewModel: ObservableObject, MarkerRenderingSupport {
    let container: ArcGISSceneContainer
    private let markerLayer = GraphicsOverlay()
    private let polylineLayer = GraphicsOverlay()
    private let polygonLayer = GraphicsOverlay()
    private let hullPolygonLayer = GraphicsOverlay()
    private let circleLayer = GraphicsOverlay()

    private(set) var controller: ArcGISMapViewController?
    private var hullPolygonController: ArcGISPolygonOverlayController?
    private var overlayScope: MapOverlayScope?
    private var didBind = false
    private var dragState: MarkerDragState = .idle
    /// 「1秒長押し → ドラッグ」ジェスチャでマーカーを掴んでいる間 true。
    private var holdDragActive = false

    private var cameraMoveEndWorkItem: DispatchWorkItem?
    private let cameraMoveEndDebounceSeconds = 0.18

    private var currentMarkerTileRasterLayer: RasterLayerState?

    private var strategyMarkerController: ArcGISStrategyController?
    private var strategyMarkerRenderer: ArcGISMarkerRenderer?
    private var strategyMarkerSubscriptions: [String: AnyCancellable] = [:]
    private var strategyMarkerStatesById: [String: MarkerState] = [:]
    /// 接続中の strategy とそのマーカー。以前は `MapViewContent` の
    /// markerRenderingStrategy / markerRenderingMarkers を毎回読んでいたが、
    /// プラグインが ``MarkerRenderingSupport`` 経由で押し込む形に反転した。
    private(set) var connectedStrategyMarkers: [MarkerState] = []
    private(set) var hasConnectedStrategy = false
    private var strategyConnectedThisPass = false

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
        cameraRestriction: CameraRestriction?,
        onMapClick: OnMapEventHandler?,
        onMapLongClick: OnMapEventHandler?,
        onCameraMoveStart: OnCameraMoveHandler?,
        onCameraMove: OnCameraMoveHandler?,
        onCameraMoveEnd: OnCameraMoveHandler?
    ) {
        // Publish marker rendering as a map-scoped capability. Add-on modules resolve it
        // from the registry; this provider never learns that clustering exists.
        // 再バインド時に前回の capability が残らないよう、登録前に空にする
        // （android-sdk の各 *MapView.kt が `registry.clear()` してから put するのと同じ）。
        state.serviceRegistry.clear()
        state.serviceRegistry.put(MarkerRenderingSupportKey.self, self)
        if didBind {
            NSLog("[MapConductor][ArcGIS] bind skipped because model is already bound")
            return
        }
        NSLog("[MapConductor][ArcGIS] bind begin")
        didBind = true

        let holder = ArcGISMapViewHolder(container: container)
        let raster = ArcGISRasterLayerController(scene: container.scene)
        self.hullPolygonController = ArcGISPolygonOverlayController(
            polygonLayer: hullPolygonLayer
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
            polygonController: ArcGISPolygonOverlayController(polygonLayer: polygonLayer),
            circleController: ArcGISCircleOverlayController(circleLayer: circleLayer),
            groundImageController: ArcGISGroundImageController(scene: container.scene),
            rasterLayerController: raster,
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
        // android-for-arcgis がコントローラ生成直後に setCameraRestriction するのと同じ位置。
        controller.setCameraRestriction(cameraRestriction)
        state.setSceneViewHolder(controller.typedHolder)
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
        state.setSceneViewHolder(nil)
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
        overlayScope?.clear()
        overlayScope = nil
        didBind = false
        NSLog("[MapConductor][ArcGIS] unbind end")
    }

    /// 「1秒長押し → ドラッグ」の移動ハンドラ。最初の移動でホールド地点のマーカーを掴み、
    /// 以降の移動でマーカーを追従させる（android の long-press ドラッグ相当）。
    func handleHoldDrag(location: CGPoint, start: CGPoint) {
        guard let controller else { return }
        if !holdDragActive {
            holdDragActive = true
            Task {
                let started = await controller.handleMarkerDragStart(screenPoint: start, mapPoint: nil)
                if started {
                    _ = await controller.handleMarkerDrag(screenPoint: location)
                } else {
                    holdDragActive = false
                }
            }
        } else {
            Task { _ = await controller.handleMarkerDrag(screenPoint: location) }
        }
    }

    func handleHoldDragEnd() {
        guard holdDragActive else { return }
        holdDragActive = false
        _ = controller?.finishMarkerDrag()
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
        // ホールドドラッグが何らかの理由で onEnded を受け取れなかった場合の保険。
        if holdDragActive {
            holdDragActive = false
            _ = controller?.finishMarkerDrag()
        }
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
            // 範囲・ズーム制限に違反していれば矩形内へ引き戻す（ArcGIS はネイティブの範囲制限
            // API が無いため）。再適用すると viewpointChanged が再発火し、そこでは補正不要に
            // なり通常フローへ進む。android-for-arcgis と同一仕様。
            if self.controller?.applyCameraRestrictionCorrectionIfNeeded(posWithVR) == true { return }
            self.controller?.notifyCameraMoveEnd(posWithVR)
            Task { [weak self] in
                await self?.strategyMarkerController?.onCameraChanged(mapCameraPosition: posWithVR)
            }
        }
        cameraMoveEndWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + cameraMoveEndDebounceSeconds, execute: workItem)
    }

    private static func computeVisibleRegion(for position: MapCameraPosition, viewportSize: CGSize?) -> VisibleRegion? {
        // 2D 側（ArcGISMapView2D）と同一の計算を使う。実体は ArcGISVisibleRegion.swift。
        arcGISComputeVisibleRegion(for: position, viewportSize: viewportSize)
    }

    func syncInfoBubbles(_ bubbles: [InfoBubble]) {
        infoBubbleCoordinator?.syncInfoBubbles(bubbles)
    }

    func updateInfoBubbleLayouts() {
        infoBubbleCoordinator?.updateAllLayouts()
    }

    /// strategy 由来のマーカーを含めたフィンガープリント。
    var strategyFingerprint: Int {
        var hasher = Hasher()
        connectedStrategyMarkers.forEach {
            hasher.combine($0.id)
            hasher.combine($0.position.latitude)
            hasher.combine($0.position.longitude)
        }
        hasher.combine(hasConnectedStrategy)
        return hasher.finalize()
    }

    // MARK: - MarkerRenderingSupport
    //
    // ArcGIS は StrategyMarkerManager を使わず独自にレンダラーを持つため、モデル自身が
    // capability を実装する。引き当ての向きは他プロバイダと同じで、クラスタリング側が
    // MapServiceRegistry から解決して connect を呼ぶ。

    @discardableResult
    func connect(strategy: Any, markers: [MarkerState]) -> Bool {
        guard strategy is AnyMarkerRenderingStrategy<Graphic> else { return false }
        strategyConnectedThisPass = true
        connectStrategyRendering(strategy)
        hasConnectedStrategy = true
        syncMarkers(markers)
        return true
    }

    func syncMarkers(_ markers: [MarkerState]) {
        connectedStrategyMarkers = markers
        syncStrategyMarkers(markers)
    }

    func disconnect() {
        connectStrategyRendering(nil)
    }

    func beginContentPass() {
        strategyConnectedThisPass = false
    }

    func endContentPass() {
        if !strategyConnectedThisPass, hasConnectedStrategy {
            disconnect()
        }
    }

    private func connectStrategyRendering(_ anyStrategy: Any?) {
        if let strategy = anyStrategy as? AnyMarkerRenderingStrategy<Graphic> {
            if strategyMarkerController == nil ||
                strategyMarkerController?.markerManager !== strategy.markerManager {
                strategyMarkerRenderer?.unbind()
                let renderer = ArcGISMarkerRenderer(markerLayer: markerLayer, container: container)
                strategyMarkerRenderer = renderer
                strategyMarkerController = ArcGISStrategyController(strategy: strategy, renderer: renderer)
                // find() の android 同等 screen 空間判定用に geo→screen 投影を注入する。
                strategyMarkerController?.markerProjector = { [weak self] geo in
                    guard let proxy = self?.container.proxy?.proxy else { return nil }
                    return proxy.screenPoint(fromLocation: geo.toArcGISPoint(spatialReference: .wgs84))?.screenPoint
                }
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
        } else {
            strategyMarkerSubscriptions.values.forEach { $0.cancel() }
            strategyMarkerSubscriptions.removeAll()
            strategyMarkerStatesById.removeAll()
            strategyMarkerRenderer?.unbind()
            strategyMarkerRenderer = nil
            strategyMarkerController?.destroy()
            strategyMarkerController = nil
            connectedStrategyMarkers = []
            hasConnectedStrategy = false
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
                guard self != nil else { return }
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
        controller.markerController.tilingOptions = content.markerTilingOptions
        if hasConnectedStrategy {
            await controller.markerController.syncMarkers([])
        } else {
            await controller.markerController.syncMarkers(content.markers)
        }
        overlayScope?.groundImageCollector.sync(content.groundImages.map { $0.state })
        let tileLayer = currentMarkerTileRasterLayer.map { RasterLayer(state: $0) }
        let allRasterLayers = content.rasterLayers + (tileLayer.map { [$0] } ?? [])
        overlayScope?.rasterLayerCollector.sync(allRasterLayers.map { $0.state })
        overlayScope?.circleCollector.sync(content.circles.map { $0.state })
        overlayScope?.polylineCollector.sync(content.polylines.map { $0.state })
        overlayScope?.polygonCollector.sync(content.polygons.map { $0.state })
        for handler in content.polygonSyncHandlers {
            let hullController = hullPolygonController
            handler.bindPolygonSync { [weak hullController] states in
                await hullController?.add(data: states)
            }
        }
        syncInfoBubbles(content.infoBubbles)
    }
}

private enum MarkerDragState {
    case idle
    case dragging
}

/// The 3D `SceneView` exposes only `interactiveNavigationDisabled`, an
/// all-or-nothing switch, so individual gestures cannot be turned off. `scroll`
/// is approximated by swallowing drags in an overlay (see `topContent` above);
/// the rest have no equivalent. Use `ArcGISMapView2D`, which supports pan, zoom
/// and rotate individually, when you need that control.
private func warnUnsupportedSceneGestures(_ ui: MapUISettings) {
    for (requested, gesture) in [
        (ui.zoomGesture, MapGesture.zoom),
        (ui.rotateGesture, MapGesture.rotate),
        (ui.tiltGesture, MapGesture.tilt),
    ] {
        MapUISettingsDiagnostics.warnIfRequested(
            requested,
            gesture: gesture,
            provider: "ArcGIS (3D SceneView)",
            reason: "SceneView can only disable all navigation at once; use ArcGISMapView2D for per-gesture control"
        )
    }
}
