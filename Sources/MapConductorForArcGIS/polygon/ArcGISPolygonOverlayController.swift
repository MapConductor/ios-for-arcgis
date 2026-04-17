import ArcGIS
import Combine
import Foundation
import MapConductorCore

@MainActor
final class ArcGISPolygonOverlayController: PolygonController<Graphic, ArcGISPolygonOverlayRenderer> {
    private var statesById: [String: PolygonState] = [:]
    private var subscriptions: [String: AnyCancellable] = [:]

    init(polygonLayer: GraphicsOverlay) {
        super.init(polygonManager: PolygonManager<Graphic>(), renderer: ArcGISPolygonOverlayRenderer(polygonLayer: polygonLayer))
    }

    func syncPolygons(_ polygons: [MapConductorCore.Polygon]) async {
        let newIds = Set(polygons.map(\.id))
        let oldIds = Set(statesById.keys)
        var next: [String: PolygonState] = [:]
        var shouldSyncList = oldIds != newIds

        for polygon in polygons {
            let state = polygon.state
            if let existingState = statesById[state.id], existingState !== state {
                subscriptions[state.id]?.cancel()
                subscriptions.removeValue(forKey: state.id)
                shouldSyncList = true
            }
            if !polygonManager.hasEntity(state.id) {
                shouldSyncList = true
            }
            next[state.id] = state
        }

        for id in oldIds.subtracting(newIds) {
            subscriptions[id]?.cancel()
            subscriptions.removeValue(forKey: id)
        }

        statesById = next

        if shouldSyncList {
            await add(data: polygons.map(\.state))
        }

        polygons.forEach { subscribeToPolygon($0.state) }
    }

    private func subscribeToPolygon(_ state: PolygonState) {
        guard subscriptions[state.id] == nil else { return }
        subscriptions[state.id] = state.asFlow()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.statesById[state.id] != nil else { return }
                Task { await self.update(state: state) }
            }
    }
}
