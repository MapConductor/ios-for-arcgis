import ArcGIS
import Combine
import Foundation
@_spi(MapConductorDriver) import MapConductorCore
import SwiftUI

public struct ArcGISMapView2D: View {
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
        ArcGISSdkInitialization2D.runOnce(sdkInitialize)
    }

    public var body: some View {
        // The provider's registry is in scope only while content is being assembled —
        // the same window in which Compose provides `LocalMapServiceRegistry` around the
        // content lambda. Bracketing the pass lets a removed plugin be noticed.
        let support = state.serviceRegistry.get(MarkerRenderingSupportKey.self)
        support?.beginContentPass()
        let mapContent = MapServiceRegistryScope.with(state.serviceRegistry) { content() }
        support?.endContentPass()
        return ArcGISMapView2DBody(
            state: state,
            cameraRestriction: cameraRestriction,
            handlers: handlers,
            content: mapContent
        )
    }
}

private struct ArcGISMapView2DBody: View {
    @ObservedObject var state: ArcGISMapViewState

    let cameraRestriction: CameraRestriction?
    let handlers: MapViewHandlers<ArcGISMapViewState>
    let content: MapViewContent

    @StateObject private var model: ArcGISMapView2DModel

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
            .interactionModes(arcGISInteractionModes(for: state.uiSettings))
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
            .onViewpointChanged(kind: .centerAndScale) { viewpoint in
                model.updateViewpoint(viewpoint)
                // InfoBubble はスクリーン座標に置くため、カメラが動くたびに追従させる
                // （3D 側 `ArcGISMapView` の onViewpointChanged / onNavigatingChanged と同じ）。
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
                model.attach(proxy: proxy)
                model.bind(
                    state: state,
                    cameraRestriction: cameraRestriction,
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
            .arcGIS2DTilt(model.visualTilt)
            // ビューポートは**傾きモディファイアの外側**で測ること。内側で測ると
            // 傾いているあいだ planeScale 倍の大きさが記録され、`visibleRegion` が
            // 実際に見えている範囲の何倍にもなる（座標の畳み込みの基準もここに合わせてある）。
            .onGeometryChange(for: CGSize.self) { $0.size } action: { model.updateViewportSize($0) }
            }

            // InfoBubble を載せるパススルーコンテナ。地図の上に重ね、バブル以外の
            // タッチは地図へ通す（3D 側 `ArcGISMapView` と同じ構成）。
            InfoBubbleContainerRepresentable2D(container: model.infoBubbleContainer)
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
        // InfoBubble の増減で `updateContent` が走らないと、マーカーをタップしても
        // バブルが同期されない（3D 側のフィンガープリントと同じく id を含める）。
        infoBubbles.forEach { hasher.combine($0.id) }
        return hasher.finalize()
    }
}

private struct InfoBubbleContainerRepresentable2D: UIViewRepresentable {
    let container: PassthroughContainerView

    func makeUIView(context: Context) -> PassthroughContainerView { container }
    func updateUIView(_ uiView: PassthroughContainerView, context: Context) {}
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

    /// `MapView` を見た目だけ傾けるための論理 tilt。
    ///
    /// `state.cameraPosition` はカメラ操作の経路によっては更新されないため、コントローラの
    /// `moveCamera` / `animateCamera` から直接受け取る（android-for-arcgis が
    /// `WrapMapView.visualTilt` を同じ場所で更新しているのと対応）。
    @Published var visualTilt: Double = 0

    /// InfoBubble（およびマーカーのドロップ／バウンスアニメーション）を描くスクリーン空間の
    /// コンテナ。3D 側 `ArcGISMapViewModel` と同じ構成。
    let infoBubbleContainer = PassthroughContainerView()
    private var infoBubbleCoordinator: InfoBubbleOverlayCoordinator?
    /// ArcGIS 2D はカメラ停止イベントを持たないため、`onViewpointChanged` の停止を
    /// デバウンスして「停止」とみなし、そこで範囲制限を補正する（3D 側と同じ考え方、
    /// android-for-arcgis の `cameraMoveEndDebounceMs` に対応）。
    private var cameraRestrictionWorkItem: DispatchWorkItem?
    private let cameraRestrictionDebounceSeconds = 0.18
    private var hullPolygonController: ArcGISPolygonOverlayController?
    private var overlayScope: MapOverlayScope?
    private var didBind = false
    /// タイル方式マーカーのラスターレイヤ（3D の同名プロパティと同じ役割）。
    private var currentMarkerTileRasterLayer: RasterLayerState?

    /// マーカークラスタリング等のプラグインへ公開する描画 capability。
    ///
    /// 3D 側（`ArcGISMapViewModel`）は独自にコントローラを持つ都合でモデル自身が
    /// `MarkerRenderingSupport` を実装しているが、2D は Core の共通レイヤ
    /// `StrategyMarkerManager` をそのまま使える（`ArcGISMarkerRenderer` は
    /// `ArcGISMapContext` があれば動き、`ArcGISMapContainer2D` が準拠しているため）。
    private lazy var strategyManager: StrategyMarkerManager<Graphic, ArcGISMarkerRenderer> = {
        let manager = StrategyMarkerManager<Graphic, ArcGISMarkerRenderer>(
            makeRenderer: { [weak self] _ in
                guard let self else { fatalError("ArcGISMapView2DModel released") }
                return ArcGISMarkerRenderer(markerLayer: self.markerLayer, container: self.container)
            },
            currentCamera: { [weak self] in self?.cameraPositionWithVisibleRegion() }
        )
        manager.onRendererCreated = { [weak self, weak manager] _ in
            // find() を android と同じ画面空間判定にするため geo→screen 投影を注入する
            // （3D 側の `markerProjector` 注入と同じ目的）。controller は
            // onRendererCreated の時点で既に生成済み。
            manager?.controller?.markerProjector = { [weak self] geo in
                self?.container.screenPoint(fromLocation: geo.toArcGISPoint(spatialReference: .wgs84))
            }
        }
        return manager
    }()

    /// ビューポートサイズを記録する。`visibleRegion` の算出に必須で、
    /// 未設定だとクラスタリングが表示範囲を求められずクラスタが一切描画されない
    /// （3D 側 `ArcGISMapViewModel.updateViewportSize` と同じ役割）。
    func updateViewportSize(_ size: CGSize) {
        container.viewportSize = size
    }

    /// クラスタ算出に必要な `visibleRegion` を付けた現在のカメラ。
    private func cameraPositionWithVisibleRegion() -> MapCameraPosition {
        let pos = container.lastCameraPosition
        return MapCameraPosition(
            position: pos.position,
            zoom: pos.zoom,
            bearing: pos.bearing,
            tilt: pos.tilt,
            paddings: pos.paddings,
            visibleRegion: arcGISComputeVisibleRegion(for: pos, viewportSize: container.viewportSize)
        )
    }
    private var dragState: MarkerDragState2D = .idle
    /// 「1秒長押し → ドラッグ」ジェスチャでマーカーを掴んでいる間 true。
    private var holdDragActive = false

    init(state: ArcGISMapViewState) {
        let map = ArcGIS.Map(basemapStyle: ArcGISDesign.toBasemapStyle(state.mapDesignType))
        // 初期カメラも moveCamera と同じく tilt の擬似表現を通す（`ArcGIS2DTiltEmulation`）。
        let initialShifted = ArcGIS2DTiltEmulation.shiftedCamera(for: state.cameraPosition)
        let initialCenter = initialShifted.center.toArcGISPoint(spatialReference: .wgs84)
        let initialScale = ArcGISMapView2DController.zoomToScale(initialShifted.zoom)
        map.initialViewpoint = Viewpoint(
            center: initialCenter,
            scale: max(1, initialScale),
            rotation: CameraBearing.toNativeHeading(state.cameraPosition.bearing)
        )

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
              let rawCenter = viewpoint.targetGeometry as? Point else { return }
        // Viewpoint の座標はマップの空間参照（既定では Web メルカトル）で返るため、
        // そのまま緯度経度として扱うとメートル値になってしまう。WGS84 へ投影してから使う。
        let center = rawCenter.projectedToWGS84()
        let lat = center.y
        let lon = center.x
        let scale = viewpoint.targetScale
        let zoom = ArcGISMapView2DController.scaleToZoom(scale)
        // 2D はカメラピッチを持てないため tilt は擬似表現（`ArcGIS2DTiltEmulation`）。
        // 直近に要求した論理カメラを手掛かりに、tilt < 0 で前進させた中心とズームを巻き戻し、
        // 論理 tilt をそのまま返す。tilt >= 0 なら素通し。
        let logical = container.lastCameraPosition
        // 回転は 2D MapView がネイティブに持つので、実際の Viewpoint から読む
        // （android-for-arcgis の `mapRotation` 読み出しと同じ 0..<360 正規化）。
        let bearing = CameraBearing.bearingFromNativeHeading(viewpoint.rotation)
        let restored = ArcGIS2DTiltEmulation.restoreLogicalCamera(
            center: GeoPoint(latitude: lat, longitude: lon),
            zoom: zoom,
            bearing: bearing,
            logicalTilt: logical.tilt
        )
        let cameraPosition = MapCameraPosition(
            position: restored.position,
            zoom: restored.zoom,
            bearing: bearing,
            tilt: logical.tilt,
            paddings: MapPaddings.Zeros
        )
        controller?.notifyCameraMove(cameraPosition)
        scheduleCameraRestrictionCorrection(cameraPosition)
        // クラスタは visibleRegion.bounds を使うため、付与したカメラを渡す。
        let cameraForCluster = MapCameraPosition(
            position: cameraPosition.position,
            zoom: cameraPosition.zoom,
            bearing: cameraPosition.bearing,
            tilt: cameraPosition.tilt,
            paddings: cameraPosition.paddings,
            visibleRegion: arcGISComputeVisibleRegion(for: cameraPosition, viewportSize: container.viewportSize)
        )
        Task { [weak self] in await self?.strategyManager.onCameraChanged(cameraForCluster) }
    }

    /// パンやズームが落ち着いてから 1 度だけ補正する。移動中に毎フレーム引き戻すと
    /// ユーザーのジェスチャーと競合するため。
    private func scheduleCameraRestrictionCorrection(_ cameraPosition: MapCameraPosition) {
        cameraRestrictionWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            _ = self.controller?.applyCameraRestrictionCorrectionIfNeeded(cameraPosition)
        }
        cameraRestrictionWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + cameraRestrictionDebounceSeconds,
            execute: workItem
        )
    }


    /// ``MapViewCoordinatorBase/screenProjectionGate(feature:)`` と同じもの。
    /// ArcGIS のビューモデルは `MapViewCoordinatorBase` を継承していないので自前で持つ。
    static func screenProjectionGate(state: ArcGISMapViewState, feature: String) -> () -> Bool {
        let registry = state.serviceRegistry
        let provider = String(describing: type(of: state))
        return { ScreenProjectionRequirement.check(registry: registry, provider: provider, feature: feature) }
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
        guard !didBind else { return }
        didBind = true

        // Publish marker rendering as a map-scoped capability. Add-on modules resolve it
        // from the registry; this provider never learns that clustering exists.
        state.serviceRegistry.put(MarkerRenderingSupportKey.self, strategyManager)

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
                onUpdateInfoBubble: { [weak self] id in
                    self?.infoBubbleCoordinator?.updateInfoBubblePosition(for: id)
                }
            ),
            polylineController: ArcGISPolylineOverlayController(polylineLayer: polylineLayer),
            polygonController: ArcGISPolygonOverlayController(polygonLayer: polygonLayer),
            circleController: ArcGISCircleOverlayController(circleLayer: circleLayer),
            groundImageController: ArcGISGroundImageController(scene: nil),
            rasterLayerController: raster,
            strategyMarkerControllerProvider: { [weak self] in self?.strategyManager.controller }
        )
        self.controller = controller
        controller.onVisualTiltChanged = { [weak self] tilt in
            guard let self else { return }
            self.visualTilt = tilt
            // ビューを傾けると地図の中身は縦に潰れる。マーカーだけは立って見えるよう、
            // アイコンを先に縦へ引き伸ばしておく（他のオーバーレイは寝たままでよい）。
            self.container.visualTiltDegrees = tilt
            controller.markerController.refreshVerticalStretch()
        }

        // クリックカスケードとスロット解決がここから kind で引く。
        // **登録を忘れるとタップに反応しなくなる。**
        controller.registerOverlayController(controller.markerController)
        controller.registerOverlayController(controller.circleController)
        controller.registerOverlayController(controller.polylineController)
        controller.registerOverlayController(controller.polygonController)
        controller.registerOverlayController(controller.groundImageController)

        let overlayScope = MapOverlayScope()
        self.overlayScope = overlayScope
        bindOverlayCollector(overlayScope.circleCollector, to: controller.circleController)
        bindOverlayCollector(overlayScope.polylineCollector, to: controller.polylineController)
        bindOverlayCollector(overlayScope.polygonCollector, to: controller.polygonController)
        bindOverlayCollector(overlayScope.rasterLayerCollector, to: controller.rasterLayerController)
        bindOverlayCollector(overlayScope.groundImageCollector, to: controller.groundImageController)

        state.setController(controller)
        // 拡張モジュール（ヒートマップ等）がオーバーレイコントローラを登録できるようにする。
        state.serviceRegistry.put(OverlayControllerRegistryKey.self, controller.overlayControllers)
        // android-for-arcgis がコントローラ生成直後に setCameraRestriction するのと同じ位置。
        controller.setCameraRestriction(cameraRestriction)
        state.setMapView2DHolder(controller.typedHolder)
        controller.setMapClickListener(listener: onMapClick)
        controller.setMapLongClickListener(listener: onMapLongClick)
        controller.setCameraMoveStartListener(listener: onCameraMoveStart)
        controller.setCameraMoveListener(listener: onCameraMove)
        controller.setCameraMoveEndListener(listener: onCameraMoveEnd)
        controller.setMapDesignTypeChangeListener(listener: { [weak state] value in state?.onMapDesignTypeChange(value: value) })

        let markerController = controller.markerController
        // タイル方式マーカーの受け口（3D の ArcGISMapView.bind と同じ配線）。
        // ここが無いと updateTileLayer が作った RasterLayerState は捨てられ、
        // タイル担当のマーカーが地図に載らない。
        markerController.markerTileRasterLayerCallback = { [weak self] state in
            self?.currentMarkerTileRasterLayer = state
        }
        // 投影は**必ず入れ物の座標へ畳む**こと。`container.screenPoint` は内側の
        // `MapView` の座標を返し、傾いているとき（と、かつて常時 200% だったとき）は
        // 入れ物と食い違う。素で使うと InfoBubble がタップからかなり離れた位置に出る。
        infoBubbleCoordinator = InfoBubbleOverlayCoordinator(
            container: infoBubbleContainer,
            project: { [weak self] point in
                guard let container = self?.container,
                      let inner = container.screenPoint(fromLocation: point.toArcGISPoint(spatialReference: .wgs84))
                else { return nil }
                return container.fromInnerToSurface(inner)
            },
            projectionGate: Self.screenProjectionGate(state: state, feature: "InfoBubble"),
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
                guard let container = self?.container,
                      let inner = container.screenPoint(fromLocation: point.toArcGISPoint(spatialReference: .wgs84))
                else { return nil }
                return container.fromInnerToSurface(inner)
            },
            projectionGate: Self.screenProjectionGate(state: state, feature: "marker animation overlay")
        )
    }

    func syncInfoBubbles(_ bubbles: [InfoBubble]) {
        infoBubbleCoordinator?.syncInfoBubbles(bubbles)
    }

    func updateInfoBubbleLayouts() {
        infoBubbleCoordinator?.updateAllLayouts()
    }

    func unbind(state: ArcGISMapViewState) {
        // 登録した capability を取り下げる。レジストリの持ち主は state で、ビューより長生きするため、
        // ここで外さないと破棄済みのコントローラを掴んだまま残る。
        state.serviceRegistry.removeProviderRegistrations()
        // クラスタ用レンダラ／コントローラも破棄する。
        strategyManager.clear()
        controller?.markerController.renderer.animationOverlay?.unbind()
        controller?.markerController.renderer.animationOverlay = nil
        infoBubbleCoordinator?.unbind()
        infoBubbleCoordinator = nil
        dragState = .idle
        // 登録済みオーバーレイコントローラ（拡張モジュール含む）を破棄する。
        controller?.destroy()
        state.setController(nil as ArcGISMapView2DController?)
        state.setMapView2DHolder(nil)
        controller = nil
        hullPolygonController = nil
        overlayScope?.clear()
        overlayScope = nil
        didBind = false
    }

    /// 長押しでマーカードラッグを arm する（android 同様）。ドラッグ可能なマーカー上なら
    /// ドラッグを開始状態にし、そうでなければマップの長押しイベントとして扱う。
    /// これにより通常のタップは奪われず InfoBubble が開ける。
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
        // ホールドドラッグが何らかの理由で onEnded を受け取れなかった場合の保険。
        if holdDragActive {
            holdDragActive = false
            _ = controller?.finishMarkerDrag()
        }
        guard dragState == .dragging else { return }
        _ = controller?.finishMarkerDrag()
        dragState = .idle
    }

    func updateContent(_ content: MapViewContent) async {
        guard let controller else { return }
        // 3D (ArcGISMapView.updateContent) と同じ並び。tilingOptions を渡さないと
        // 大量マーカーのページで全件が既定のタイル担当（minMarkerCount=2000）に降格され、
        // かつタイルレイヤの受け口も無いため**何も表示されない**（postoffice で顕在化）。
        controller.markerController.tilingOptions = content.markerTilingOptions
        await controller.markerController.syncMarkers(content.markers)
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
        // タイル方式マーカーのラスターレイヤを content のレイヤに合流させる
        // （syncMarkers が先。その中で markerTileRasterLayerCallback が発火して
        // currentMarkerTileRasterLayer が更新される）。
        let tileLayer = currentMarkerTileRasterLayer.map { RasterLayer(state: $0) }
        let allRasterLayers = content.rasterLayers + (tileLayer.map { [$0] } ?? [])
        overlayScope?.rasterLayerCollector.sync(allRasterLayers.map { $0.state })
        syncInfoBubbles(content.infoBubbles)
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

/// ArcGIS drives 2D interaction through an allow-list. A 2D `MapView` has no
/// camera pitch at all, so `tiltGesture` has nothing to switch off.
private func arcGISInteractionModes(for ui: MapUISettings) -> MapViewInteractionModes {
        MapUISettingsDiagnostics.warnIfRequested(
            ui.tiltGesture,
            gesture: .tilt,
            provider: "ArcGIS (2D)",
            reason: "a 2D map has no camera pitch"
        )
        var modes: MapViewInteractionModes = []
        if ui.scrollGesture { modes.insert(.pan) }
        if ui.zoomGesture { modes.insert(.zoom) }
        if ui.rotateGesture { modes.insert(.rotate) }
        return modes
    }
