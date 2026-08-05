import ArcGIS
import Combine
import CoreGraphics
import Foundation
import MapConductorCore
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

    private static let tileSize = 256

    init(
        markerLayer: GraphicsOverlay,
        container: any ArcGISMapContext,
        onUpdateInfoBubble: @escaping (String) -> Void
    ) {
        self.container = container
        self.onUpdateInfoBubble = onUpdateInfoBubble
        let markerManager = MarkerManager<Graphic>.defaultManager()
        super.init(
            markerManager: markerManager,
            renderer: ArcGISMarkerRenderer(markerLayer: markerLayer, container: container)
        )
    }

    func syncMarkers(_ markers: [MapConductorCore.Marker]) async {
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

    /// android-for-arcgis の `ArcGISMarkerController.find()` と同じく、最近傍マーカーを
    /// 「アイコン矩形 + tapTolerance」で判定する。半径固定だと大きいアイコンは端が反応せず、
    /// 小さいアイコンは離れていても反応してしまうため、アイコンの実寸とアンカーを使う。
    ///
    /// 投影できない場合（proxy 未接続など）は判定できないので、従来どおり最近傍を返す。
    override func find(position: GeoPointProtocol) -> MarkerEntity<Graphic>? {
        guard let nearest = markerManager.findNearest(position: position) else { return nil }
        // 基底の `find` は nonisolated だが、呼び出し元はタップ処理（`handleTap`）だけで
        // 常にメインアクター上。投影 API（`ArcGISMapContext`）はメインアクター隔離のため、
        // ここで隔離済みであることを明示する。
        return MainActor.assumeIsolated {
            guard let container,
                  let touchScreen = container.screenPoint(
                      fromLocation: position.toArcGISPoint(spatialReference: .wgs84)
                  ),
                  let markerScreen = container.screenPoint(
                      fromLocation: nearest.state.position.toArcGISPoint(spatialReference: .wgs84)
                  ) else {
                return nearest
            }
            return MarkerHitTest.hitsIcon(
                touchScreen: touchScreen,
                markerScreen: markerScreen,
                state: nearest.state
            ) ? nearest : nil
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

    private func setupTileRenderer() {
        let routeId = "mapconductor-arcgis-markers-\(UUID().uuidString)"
        let contentScale = Double(UIScreen.main.scale)
        let baseCallback = tilingOptions.iconScaleCallback
        let scaledCallback: ((MarkerState, Int) -> Double)? = { state, zoom in
            (baseCallback?(state, zoom) ?? 1.0) * contentScale
        }
        let renderer = MarkerTileRenderer<Graphic>(
            markerManager: markerManager,
            tileSize: Self.tileSize,
            cacheSizeBytes: tilingOptions.cacheSize,
            debugTileOverlay: tilingOptions.debugTileOverlay,
            iconScaleCallback: scaledCallback
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
            source: .urlTemplate(template: urlTemplate, tileSize: tileRenderer.tileSize),
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
    /// 「アイコン矩形 + tapTolerance」で判定する。以前はアイコンの外接円を使った半径判定
    /// （`max(22, 最大辺 / 2)`）で、同じアイコンでもタップとドラッグで当たる範囲が違っていた。
    private func draggableMarker(at screenPoint: CGPoint) -> MarkerEntity<Graphic>? {
        guard let container else { return nil }

        var bestEntity: MarkerEntity<Graphic>?
        var bestDistance = CGFloat.infinity

        for entity in markerManager.allEntities() where entity.state.draggable {
            let location = entity.state.position.toArcGISPoint(spatialReference: .wgs84)
            guard let projected = container.screenPoint(fromLocation: location) else { continue }
            guard MarkerHitTest.hitsIcon(
                touchScreen: screenPoint,
                markerScreen: projected,
                state: entity.state
            ) else { continue }

            let distance = hypot(screenPoint.x - projected.x, screenPoint.y - projected.y)
            if distance < bestDistance {
                bestDistance = distance
                bestEntity = entity
            }
        }

        return bestEntity
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
