import ArcGIS
import Combine
import Foundation
import MapConductorCore

@MainActor
final class ArcGISGroundImageController: GroundImageController<ArcGISGroundImageHandle, ArcGISGroundImageOverlayRenderer> {
    private var statesById: [String: GroundImageState] = [:]
    private var subscriptions: [String: AnyCancellable] = [:]

    init(scene: ArcGIS.Scene) {
        super.init(groundImageManager: GroundImageManager<ArcGISGroundImageHandle>(), renderer: ArcGISGroundImageOverlayRenderer(scene: scene))
    }

    func syncGroundImages(_ images: [MapConductorCore.GroundImage]) async {
        let newIds = Set(images.map(\.id))
        let oldIds = Set(statesById.keys)
        var next: [String: GroundImageState] = [:]
        var shouldSyncList = oldIds != newIds

        for image in images {
            let state = image.state
            if let existingState = statesById[state.id], existingState !== state {
                subscriptions[state.id]?.cancel()
                subscriptions.removeValue(forKey: state.id)
                shouldSyncList = true
            }
            if !groundImageManager.hasEntity(state.id) {
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
            await add(data: images.map(\.state))
        }

        images.forEach { subscribeToGroundImage($0.state) }
    }

    private func subscribeToGroundImage(_ state: GroundImageState) {
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
