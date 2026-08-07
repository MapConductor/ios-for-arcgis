import ArcGIS
import CoreGraphics
import Foundation
import MapConductorCore

final class ArcGISMapView2DController: MapViewControllerProtocol {
    let holder: AnyMapViewHolder
    let typedHolder: ArcGISMapView2DHolder
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

    /// クラスタ等のプラグインが接続中に使う描画コントローラ。3D 側と同じく、
    /// 接続状況が変わるため毎回 provider から取り直す。
    private let strategyMarkerControllerProvider: () -> ArcGISStrategyMarkerController?

    private var cameraMoveStartListener: OnCameraMoveHandler?
    private var cameraMoveListener: OnCameraMoveHandler?
    private var cameraMoveEndListener: OnCameraMoveHandler?

    /// パン範囲の制限に使うクランプ。
    ///
    /// ArcGIS にはカメラ *範囲*（矩形）の制限 API が無いため、パンは android-for-arcgis と
    /// 同じくカメラ停止時に矩形内へクランプして再適用する方式で制限する。
    /// ズームは ``applyScaleLimits(_:)`` でネイティブの `Map.minScale` / `Map.maxScale` を使う。
    private let cameraRestrictionClamp = CameraRestrictionClamp()

    func setCameraRestriction(_ restriction: CameraRestriction?) {
        cameraRestrictionClamp.set(restriction)
        applyScaleLimits(restriction)
    }

    /// ズーム制限を ArcGIS のネイティブなスケール制限へ変換して適用する。
    ///
    /// ArcGIS の縮尺は分母（1:N）で表され、`Map.minScale` が「最も引いた側」＝ N が大きい方、
    /// `Map.maxScale` が「最も寄せた側」＝ N が小さい方に対応する。統一ズーム（Google 準拠）とは
    /// 大小が逆になるため、`minZoom → minScale` / `maxZoom → maxScale` と読み替えて変換する。
    ///
    /// `nil` は ArcGIS 側で「制限なし」を意味するので、未指定時はそのまま `nil` を渡す。
    ///
    /// 縮尺は投影座標系上の公称縮尺で緯度に依存しないため（``zoomToScale(_:)``）、
    /// `Map.minScale` / `maxScale` のような緯度に依らない定数へそのまま変換できる。
    private func applyScaleLimits(_ restriction: CameraRestriction?) {
        typedHolder.map.minScale = restriction?.minZoom.map { Self.zoomToScale($0) }
        typedHolder.map.maxScale = restriction?.maxZoom.map { Self.zoomToScale($0) }
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

    init(
        holder: ArcGISMapView2DHolder,
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

    func setCameraMoveStartListener(listener: OnCameraMoveHandler?) { cameraMoveStartListener = listener }
    func setCameraMoveListener(listener: OnCameraMoveHandler?) { cameraMoveListener = listener }
    func setCameraMoveEndListener(listener: OnCameraMoveHandler?) { cameraMoveEndListener = listener }
    func setMapClickListener(listener: OnMapEventHandler?) { mapClickListener = listener }
    func setMapLongClickListener(listener: OnMapEventHandler?) { mapLongClickListener = listener }
    func setMapInitializedListener(listener: OnMapInitializedHandler?) { mapInitializedListener = listener }
    func setMapDesignTypeChangeListener(listener: ArcGISDesignTypeChangeHandler?) { mapDesignTypeChangeListener = listener }

    /// 論理 tilt が変わったことをビュー層へ伝える。2D はカメラピッチを持てないため、
    /// `ArcGIS2DTiltModifier` が `MapView` 自体を傾けて見た目を作る。
    var onVisualTiltChanged: ((Double) -> Void)?

    func moveCamera(position: MapCameraPosition) {
        typedHolder.mapView.lastCameraPosition = position
        onVisualTiltChanged?(position.tilt)
        Task { @MainActor in
            let viewpoint = toViewpoint(position)
            _ = await typedHolder.mapView.proxy?.proxy.setViewpoint(viewpoint)
        }
    }

    func animateCamera(position: MapCameraPosition, duration: Long) {
        typedHolder.mapView.lastCameraPosition = position
        onVisualTiltChanged?(position.tilt)
        Task { @MainActor in
            let viewpoint = toViewpoint(position)
            cameraMoveStartListener?(position)
            await typedHolder.mapView.proxy?.proxy.setViewpoint(viewpoint, duration: Double(duration) / 1000)
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
        Task { @MainActor in
            // MapViewProxy.setViewpointGeometry applies the screen-space padding (points) on every
            // edge while framing the geometry — the padding-aware equivalent of setViewpoint.
            _ = await typedHolder.mapView.proxy?.proxy.setViewpointGeometry(envelope, padding: CGFloat(max(0, padding)))
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
        // 登録済みオーバーレイ（拡張モジュール含む）へ伝播する。
        overlayControllers.dispatchCameraChanged(cameraPosition)
        typedHolder.mapView.lastCameraPosition = cameraPosition
        cameraMoveEndListener?(cameraPosition)
    }

    func notifyMapClick(_ point: GeoPoint) { mapClickListener?(point) }
    func notifyMapLongClick(_ point: GeoPoint) { mapLongClickListener?(point) }
    func notifyMapInitialized() { mapInitializedListener?(.MapCreated) }

    @MainActor
    func handleTap(screenPoint: CGPoint, mapPoint: Point?) async -> Bool {
        guard let touchPosition = mapPoint?.projectedToWGS84().toGeoPoint() else { return false }

        // ヒット判定（アイコン矩形 + tapTolerance）は find() が行う。
        if let markerEntity = markerController.find(position: touchPosition) {
            markerController.dispatchClick(state: markerEntity.state)
            return true
        }
        // クラスタ等のプラグインが描画したマーカー。3D 側 `ArcGISMapViewController` と同じく、
        // content 由来のマーカーの次に判定する（こちらは Core の StrategyMarkerController が
        // 同じアイコン矩形判定を行う）。
        if let strategyController = strategyMarkerControllerProvider(),
           let markerEntity = strategyController.find(position: touchPosition) {
            strategyController.dispatchClick(markerEntity.state)
            return true
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
            touchPosition = mapPoint.projectedToWGS84().toGeoPoint()
        } else if let proxy = typedHolder.mapView.proxy?.proxy,
                  let resolvedPoint = proxy.location(fromScreenPoint: screenPoint) {
            touchPosition = resolvedPoint.projectedToWGS84().toGeoPoint()
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
        markerController.handleDrag(at: mapPoint.projectedToWGS84().toGeoPoint())
    }

    @MainActor
    func handleMarkerDragEnd(screenPoint: CGPoint) async -> Bool {
        let touchPosition = await toGeoPoint(from: screenPoint)
        return markerController.handleDragEnd(at: touchPosition)
    }

    @MainActor
    func handleMarkerDragEnd(mapPoint: Point) -> Bool {
        markerController.handleDragEnd(at: mapPoint.projectedToWGS84().toGeoPoint())
    }

    @MainActor
    func cancelMarkerDrag() -> Bool {
        markerController.cancelDrag()
    }

    @MainActor
    func finishMarkerDrag() -> Bool {
        markerController.handleDragEnd(at: nil)
    }

    /// 2D `MapView` はカメラピッチを持てないため、tilt < 0（上向き）は中心の前進と
    /// ズーム補正で近似する（`ArcGIS2DTiltEmulation`）。tilt >= 0 は他プロバイダと同じく
    /// 指定位置がそのまま画面中心に来る。
    private func toViewpoint(_ position: MapCameraPosition) -> Viewpoint {
        let shifted = ArcGIS2DTiltEmulation.shiftedCamera(for: position)
        let point = shifted.center.toArcGISPoint(spatialReference: .wgs84)
        let scale = ArcGISMapView2DController.zoomToScale(shifted.zoom)
        // 2D MapView は回転をネイティブに扱えるので bearing はそのまま渡す
        // （android-for-arcgis の `toViewpoint` と同じ 1:1 対応）。
        return Viewpoint(center: point, scale: scale, rotation: position.bearing)
    }

    @MainActor
    private func toGeoPoint(from screenPoint: CGPoint) async -> GeoPoint? {
        guard let proxy = typedHolder.mapView.proxy?.proxy,
              let point = proxy.location(fromScreenPoint: screenPoint) else {
            return nil
        }
        return point.projectedToWGS84().toGeoPoint()
    }

    /// 統一ズーム（Google 準拠）→ ArcGIS の縮尺分母。
    ///
    /// ArcGIS が扱う縮尺は Web メルカトルの **投影座標系上** の縮尺（公称縮尺）で、
    /// 緯度による補正は含まない。Google のズームも同じく投影座標系（256px タイルで世界一周）で
    /// 定義されているため、両者は緯度に依存しない 1 対 1 の対応になる。
    ///
    /// 以前はここに `cos(latitude)` を掛けて「地表の実距離」に直していたため、高緯度ほど
    /// 縮尺が小さく（＝寄りすぎに）なっていた。緯度 65 度で Google 比 2.4 倍ほど拡大されており、
    /// 同じ `MapCameraPosition` を渡しても Google Maps と表示範囲が一致しなかった。
    ///
    /// - `resolution`: 1 スクリーンピクセルあたりの投影メートル。
    /// - `96 / 0.0254`: ESRI 標準の 96 DPI をメートルあたりのピクセル数へ換算した係数。
    static func zoomToScale(_ zoom: Double) -> Double {
        let resolution = Earth.circumferenceMeters / (256.0 * pow(2.0, zoom))
        return resolution * pixelsPerMeterAt96DPI
    }

    /// ``zoomToScale(_:)`` の逆変換。
    static func scaleToZoom(_ scale: Double) -> Double {
        let resolution = scale / pixelsPerMeterAt96DPI
        return log2(Earth.circumferenceMeters / (256.0 * resolution))
    }

    /// 96 DPI（ESRI が縮尺計算に用いる標準値）における 1 メートルあたりのピクセル数。
    private static let pixelsPerMeterAt96DPI: Double = 96.0 / 0.0254
}
