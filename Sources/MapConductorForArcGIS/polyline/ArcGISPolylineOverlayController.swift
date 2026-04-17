import ArcGIS
import Combine
import Foundation
import MapConductorCore

@MainActor
final class ArcGISPolylineOverlayController: PolylineController<Graphic, ArcGISPolylineOverlayRenderer> {
    private var statesById: [String: PolylineState] = [:]
    private var subscriptions: [String: AnyCancellable] = [:]

    init(polylineLayer: GraphicsOverlay) {
        super.init(polylineManager: PolylineManager<Graphic>(), renderer: ArcGISPolylineOverlayRenderer(polylineLayer: polylineLayer))
    }

    func syncPolylines(_ polylines: [MapConductorCore.Polyline]) async {
        let newIds = Set(polylines.map(\.id))
        let oldIds = Set(statesById.keys)
        var next: [String: PolylineState] = [:]
        var shouldSyncList = oldIds != newIds

        for polyline in polylines {
            let state = polyline.state
            if let existingState = statesById[state.id], existingState !== state {
                subscriptions[state.id]?.cancel()
                subscriptions.removeValue(forKey: state.id)
                shouldSyncList = true
            }
            if !polylineManager.hasEntity(state.id) {
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
            await add(data: polylines.map(\.state))
        }

        polylines.forEach { subscribeToPolyline($0.state) }
    }

    private func subscribeToPolyline(_ state: PolylineState) {
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
