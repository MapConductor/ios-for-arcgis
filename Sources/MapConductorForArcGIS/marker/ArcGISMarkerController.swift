import ArcGIS
import Combine
import CoreGraphics
import Foundation
@_spi(MapConductorDriver) import MapConductorCore
import UIKit

@MainActor
final class ArcGISMarkerController: AbstractMarkerController<Graphic, ArcGISMarkerRenderer> {
    private var markerStatesById: [String: MarkerState] = [:]
    private var markerSubscriptions: [String: AnyCancellable] = [:]
    private var draggingMarkerId: String?

    private weak var container: (any ArcGISMapContext)?
    private let onUpdateInfoBubble: (String) -> Void

    // MARK: - Marker tiling

    var tilingOptions: MarkerTilingOptions = .Default
    var markerTileRasterLayerCallback: ((RasterLayerState?) -> Void)?

    private var tileRenderer: MarkerTileRenderer<Graphic>?
    private var tileRouteId: String?
    private var tiledMarkerIds: Set<String> = []
    private var tileRasterLayerId: String?
    private let defaultMarkerIconForTiling: BitmapIcon = DefaultMarkerIcon().toBitmapIcon()

    /// The marker tile layer's declared side.
    private static let tileSize = 256

    /// Whether the map lays tiles out in points (2D `MapView`) rather than
    /// across 256 device pixels (3D `SceneView`). See ``renderTileSize``.
    private let tilesInPoints: Bool

    /// 2D の tilt 表現が変わったときに、マーカーの縦補正を掛け直す。
    func refreshVerticalStretch() {
        renderer.refreshVerticalStretch()
    }

    init(
        markerLayer: GraphicsOverlay,
        container: any ArcGISMapContext,
        tilesInPoints: Bool = false,
        onUpdateInfoBubble: @escaping (String) -> Void
    ) {
        self.container = container
        self.tilesInPoints = tilesInPoints
        self.onUpdateInfoBubble = onUpdateInfoBubble
        let markerManager = MarkerManager<Graphic>.defaultManager()
        super.init(
            markerManager: markerManager,
            renderer: ArcGISMarkerRenderer(markerLayer: markerLayer, container: container)
        )
    }

    /// 同一一覧の再送を見抜く門番。詳細は型のコメントに。
    private var syncIdentity = MarkerListIdentity()

    func syncMarkers(_ markers: [MapConductorCore.Marker]) async {
        // 同じ一覧の再送は入口で帰す。SwiftUI はカメラが動くたびに body を
        // 再評価し、そのたびに全マーカーがここへ来る。なぜそれが実害か
        // （144k 件で操作の 89% が凍った）は core の MarkerListIdentity に。
        guard syncIdentity.shouldProcess(markers) else {
            _ = markers // 何も要らない。既に全部届いている。
            return
        }
        let newIds = Set(markers.map(\.id))
        let oldIds = Set(markerStatesById.keys)
        var next: [String: MarkerState] = [:]
        var shouldSyncList = oldIds != newIds

        for marker in markers {
            let state = marker.state
            if let existingState = markerStatesById[state.id], existingState !== state {
                markerSubscriptions[state.id]?.cancel()
                markerSubscriptions.removeValue(forKey: state.id)
                shouldSyncList = true
            }
            if !markerManager.hasEntity(state.id) {
                shouldSyncList = true
            }
            next[state.id] = state
        }

        for id in oldIds.subtracting(newIds) {
            markerSubscriptions[id]?.cancel()
            markerSubscriptions.removeValue(forKey: id)
        }

        markerStatesById = next

        if shouldSyncList {
            await add(data: markers.map(\.state))
        }

        markers.forEach { subscribeToMarker($0.state) }
    }

    /// android-sdk の `AbstractMarkerController.find()` と同じく、タップ点の周りのマーカーを候補にし、
    /// 指の下にアイコン（ラベル込み）が描かれているものを優先する（``MarkerHitTest/pick``）。
    ///
    /// 投影できない場合（proxy 未接続など）は判定できないので、従来どおり最近傍を返す。
    override func find(position: GeoPointProtocol) -> MarkerEntity<Graphic>? {
        // 基底の `find` は nonisolated だが、呼び出し元はタップ処理（`handleTap`）だけで
        // 常にメインアクター上。投影 API（`ArcGISMapContext`）はメインアクター隔離のため、
        // ここで隔離済みであることを明示する。
        return MainActor.assumeIsolated {
            guard let container,
                  let touchScreen = container.screenPoint(
                      fromLocation: position.toArcGISPoint(spatialReference: .wgs84)
                  ) else {
                return markerManager.findNearest(position: position)
            }
            let project: (GeoPointProtocol) -> CGPoint? = {
                container.screenPoint(fromLocation: $0.toArcGISPoint(spatialReference: .wgs84))
            }
            guard let bounds = MarkerHitTest.searchBounds(
                position: position,
                touchScreen: touchScreen,
                project: project
            ) else { return nil }
            return MarkerHitTest.pick(
                touchScreen: touchScreen,
                candidates: markerManager.findMarkersInBounds(bounds),
                state: { $0.state },
                project: project
            )
        }
    }

    override func add(data: [MarkerState]) async {
        guard tilingOptions.enabled else {
            await super.add(data: data)
            return
        }
        if tileRenderer == nil { setupTileRenderer() }

        let shouldTileAll = data.count >= tilingOptions.minMarkerCount
        var localTiledMarkerIds = tiledMarkerIds
        let result = await MarkerIngestionEngine.ingest(
            data: data,
            markerManager: markerManager,
            renderer: renderer,
            defaultMarkerIcon: defaultMarkerIconForTiling,
            tilingEnabled: tilingOptions.enabled,
            tiledMarkerIds: &localTiledMarkerIds,
            shouldTile: { [shouldTileAll] _ in shouldTileAll }
        )
        tiledMarkerIds = localTiledMarkerIds

        if result.tiledDataChanged, let tileRenderer {
            tileRenderer.invalidate()
            updateTileLayer(hasTiledMarkers: result.hasTiledMarkers)
        }
    }

    /// Pixels a marker tile is drawn at.
    ///
    /// The 3D `SceneView` shows a tile across 256 device pixels, so a 256 px
    /// tile is shown 1:1. The 2D `MapView` lays the declared 256 out in
    /// points -- 512 device pixels at scale 2 -- and a 256 px tile was
    /// stretched to twice its size: pins came out twice as large with soft
    /// edges (iPad Pro, 75 px against Google's 38). Drawn at the screen's
    /// scale, the 2D tile fills its points pixel for pixel, like the
    /// `retinaAwareTileSize` of the Google and MapLibre controllers.
    private var renderTileSize: Int {
        tilesInPoints ? Self.tileSize * max(1, Int(UIScreen.main.scale)) : Self.tileSize
    }

    private func setupTileRenderer() {
        let routeId = "mapconductor-arcgis-markers-\(UUID().uuidString)"
        let contentScale = Double(UIScreen.main.scale)
        let baseCallback = tilingOptions.iconScaleCallback
        let scaledCallback: ((MarkerState, Int) -> Double)? = { state, zoom in
            (baseCallback?(state, zoom) ?? 1.0) * contentScale
        }
        let renderer = MarkerTileRenderer<Graphic>(
            markerManager: markerManager,
            tileSize: renderTileSize,
            cacheSizeBytes: tilingOptions.cacheSize,
            debugTileOverlay: tilingOptions.debugTileOverlay,
            iconScaleCallback: scaledCallback,
            // MapLibre と同じく tilingOptions から。渡し忘れると 14px の間引きが
            // 黙って無効になり、密なデータで描画も突き合わせも重くなる（実際に
            // ここが 0 のままだった）。
            declutterPx: tilingOptions.declutterPx
        )
        TileServerRegistry.get().register(routeId: routeId, provider: renderer)
        tileRenderer = renderer
        tileRouteId = routeId
    }

    private func updateTileLayer(hasTiledMarkers: Bool) {
        guard hasTiledMarkers, let routeId = tileRouteId, let tileRenderer else {
            if tileRasterLayerId != nil {
                tileRasterLayerId = nil
                markerTileRasterLayerCallback?(nil)
            }
            return
        }
        let server = TileServerRegistry.get()
        let urlTemplate = server.urlTemplate(routeId: routeId, tileSize: tileRenderer.tileSize)
        let layerId = tileRasterLayerId ?? "marker-tile-\(routeId)"
        tileRasterLayerId = layerId
        let state = RasterLayerState(
            source: .urlTemplate(template: urlTemplate, tileSize: Self.tileSize),
            id: layerId
        )
        markerTileRasterLayerCallback?(state)
    }

    func unbind() {
        markerSubscriptions.values.forEach { $0.cancel() }
        markerSubscriptions.removeAll()
        markerStatesById.removeAll()
        draggingMarkerId = nil
        tileRenderer = nil
        if let routeId = tileRouteId {
            TileServerRegistry.get().unregister(routeId: routeId)
        }
        tileRouteId = nil
        tiledMarkerIds.removeAll()
        tileRasterLayerId = nil
        markerTileRasterLayerCallback = nil
        renderer.unbind()
        destroy()
    }

    func handleDragStart(screenPoint: CGPoint) -> Bool {
        guard let entity = draggableMarker(at: screenPoint) else { return false }
        return handleDragStart(markerId: entity.state.id)
    }

    func handleDragStart(markerId: String) -> Bool {
        guard let state = markerManager.getEntity(markerId)?.state,
              state.draggable else { return false }
        draggingMarkerId = markerId
        dispatchDragStart(state: state)
        onUpdateInfoBubble(markerId)
        return true
    }

    func handleDrag(at position: GeoPoint) -> Bool {
        guard let markerId = draggingMarkerId,
              let entity = markerManager.getEntity(markerId) else {
            return false
        }
        entity.marker?.geometry = position.toArcGISPoint(spatialReference: .wgs84)
        let state = entity.state
        state.position = position
        dispatchDrag(state: state)
        onUpdateInfoBubble(markerId)
        return true
    }

    func handleDragEnd(at position: GeoPoint?) -> Bool {
        guard let markerId = draggingMarkerId,
              let state = markerManager.getEntity(markerId)?.state else {
            draggingMarkerId = nil
            return false
        }
        draggingMarkerId = nil
        if let position {
            markerManager.getEntity(markerId)?.marker?.geometry = position.toArcGISPoint(spatialReference: .wgs84)
            state.position = position
        }
        dispatchDragEnd(state: state)
        onUpdateInfoBubble(markerId)
        return true
    }

    func cancelDrag() -> Bool {
        let wasDragging = draggingMarkerId != nil
        draggingMarkerId = nil
        return wasDragging
    }

    /// ドラッグ開始時のヒットテスト。タップ（``find(position:)``）と同じ
    /// ``MarkerHitTest/pick`` の規則で選ぶ。以前はアイコンの外接円を使った半径判定
    /// （`max(22, 最大辺 / 2)`）で、同じアイコンでもタップとドラッグで当たる範囲が違っていた。
    private func draggableMarker(at screenPoint: CGPoint) -> MarkerEntity<Graphic>? {
        guard let container else { return nil }
        return MarkerHitTest.pick(
            touchScreen: screenPoint,
            candidates: markerManager.allEntities().filter { $0.state.draggable },
            state: { $0.state },
            project: { container.screenPoint(fromLocation: $0.toArcGISPoint(spatialReference: .wgs84)) }
        )
    }

    private func subscribeToMarker(_ state: MarkerState) {
        guard markerSubscriptions[state.id] == nil else { return }
        markerSubscriptions[state.id] = state.asFlow()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.markerStatesById[state.id] != nil else { return }
                self.onUpdateInfoBubble(state.id)
                Task {
                    await self.update(state: state)
                    self.onUpdateInfoBubble(state.id)
                }
            }
    }
}
