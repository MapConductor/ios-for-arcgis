import ArcGIS
import Combine
import CoreGraphics
import Foundation
import MapConductorCore

@MainActor
final class ArcGISMarkerController: AbstractMarkerController<Graphic, ArcGISMarkerRenderer> {
    private var markerStatesById: [String: MarkerState] = [:]
    private var markerSubscriptions: [String: AnyCancellable] = [:]
    private var draggingMarkerId: String?

    private weak var container: ArcGISSceneContainer?
    private let onUpdateInfoBubble: (String) -> Void

    init(
        markerLayer: GraphicsOverlay,
        container: ArcGISSceneContainer,
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

    override func find(position: GeoPointProtocol) -> MarkerEntity<Graphic>? {
        markerManager.findNearest(position: position)
    }

    func unbind() {
        markerSubscriptions.values.forEach { $0.cancel() }
        markerSubscriptions.removeAll()
        markerStatesById.removeAll()
        draggingMarkerId = nil
        renderer.unbind()
        destroy()
    }

    func handleDragStart(screenPoint: CGPoint) -> Bool {
        guard let entity = draggableMarker(at: screenPoint) else { return false }
        draggingMarkerId = entity.state.id
        dispatchDragStart(state: entity.state)
        onUpdateInfoBubble(entity.state.id)
        return true
    }

    func handleDrag(at position: GeoPoint) -> Bool {
        guard let markerId = draggingMarkerId,
              let state = markerManager.getEntity(markerId)?.state else {
            return false
        }
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

    private func draggableMarker(at screenPoint: CGPoint) -> MarkerEntity<Graphic>? {
        guard let proxy = container?.proxy?.proxy else { return nil }

        var bestEntity: MarkerEntity<Graphic>?
        var bestDistance = CGFloat.infinity

        for entity in markerManager.allEntities() where entity.state.draggable {
            let location = entity.state.position.toArcGISPoint(spatialReference: .wgs84)
            guard let projected = proxy.screenPoint(fromLocation: location)?.screenPoint else { continue }

            let icon = (entity.state.icon ?? DefaultMarkerIcon()).toBitmapIcon()
            let radius = max(22, max(icon.size.width, icon.size.height) * 0.5)
            let distance = hypot(screenPoint.x - projected.x, screenPoint.y - projected.y)
            if distance <= radius, distance < bestDistance {
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
