import ArcGIS
import Combine
import Foundation
import MapConductorCore

@MainActor
final class ArcGISRasterLayerController: RasterLayerController<Layer, ArcGISRasterLayerOverlayRenderer> {
    private var statesById: [String: RasterLayerState] = [:]
    private var subscriptions: [String: AnyCancellable] = [:]

    init(scene: ArcGIS.Scene) {
        super.init(rasterLayerManager: RasterLayerManager<Layer>(), renderer: ArcGISRasterLayerOverlayRenderer(scene: scene))
    }

    func syncRasterLayers(_ layers: [MapConductorCore.RasterLayer]) async {
        let newIds = Set(layers.map(\.id))
        let oldIds = Set(statesById.keys)
        var next: [String: RasterLayerState] = [:]
        var shouldSyncList = oldIds != newIds

        for layer in layers {
            let state = layer.state
            if let existingState = statesById[state.id], existingState !== state {
                subscriptions[state.id]?.cancel()
                subscriptions.removeValue(forKey: state.id)
                shouldSyncList = true
            }
            if !rasterLayerManager.hasEntity(state.id) {
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
            await add(data: layers.map(\.state))
        }

        layers.forEach { subscribeToRasterLayer($0.state) }
    }

    private func subscribeToRasterLayer(_ state: RasterLayerState) {
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
