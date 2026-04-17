import ArcGIS
import Combine
import Foundation
import MapConductorCore

@MainActor
final class ArcGISCircleOverlayController: CircleController<Graphic, ArcGISCircleOverlayRenderer> {
    private var statesById: [String: CircleState] = [:]
    private var subscriptions: [String: AnyCancellable] = [:]

    init(circleLayer: GraphicsOverlay) {
        super.init(circleManager: CircleManager<Graphic>(), renderer: ArcGISCircleOverlayRenderer(circleLayer: circleLayer))
    }

    func syncCircles(_ circles: [MapConductorCore.Circle]) async {
        let newIds = Set(circles.map(\.id))
        let oldIds = Set(statesById.keys)
        var next: [String: CircleState] = [:]
        var shouldSyncList = oldIds != newIds

        for circle in circles {
            let state = circle.state
            if let existingState = statesById[state.id], existingState !== state {
                subscriptions[state.id]?.cancel()
                subscriptions.removeValue(forKey: state.id)
                shouldSyncList = true
            }
            if !circleManager.hasEntity(state.id) {
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
            await add(data: circles.map(\.state))
        }

        circles.forEach { subscribeToCircle($0.state) }
    }

    private func subscribeToCircle(_ state: CircleState) {
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
