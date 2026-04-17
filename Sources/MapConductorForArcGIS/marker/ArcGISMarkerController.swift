import ArcGIS
import Combine
import Foundation
import MapConductorCore

@MainActor
final class ArcGISMarkerController: AbstractMarkerController<Graphic, ArcGISMarkerRenderer> {
    private var markerStatesById: [String: MarkerState] = [:]
    private var markerSubscriptions: [String: AnyCancellable] = [:]

    init(markerLayer: GraphicsOverlay) {
        let markerManager = MarkerManager<Graphic>.defaultManager()
        super.init(markerManager: markerManager, renderer: ArcGISMarkerRenderer(markerLayer: markerLayer))
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
        destroy()
    }

    private func subscribeToMarker(_ state: MarkerState) {
        guard markerSubscriptions[state.id] == nil else { return }
        markerSubscriptions[state.id] = state.asFlow()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.markerStatesById[state.id] != nil else { return }
                Task { await self.update(state: state) }
            }
    }
}
