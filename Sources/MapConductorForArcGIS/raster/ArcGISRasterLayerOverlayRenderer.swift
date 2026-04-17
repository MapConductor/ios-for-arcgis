import ArcGIS
import Foundation
import MapConductorCore

@MainActor
final class ArcGISRasterLayerOverlayRenderer: AbstractRasterLayerOverlayRenderer<Layer> {
    private weak var scene: ArcGIS.Scene?

    init(scene: ArcGIS.Scene) {
        self.scene = scene
        super.init()
    }

    override func createLayer(state: RasterLayerState) async -> Layer? {
        guard let scene, let layer = makeLayer(from: state) else { return nil }
        apply(state: state, to: layer)
        scene.addOperationalLayer(layer)
        return layer
    }

    override func updateLayerProperties(
        layer: Layer,
        current: RasterLayerEntity<Layer>,
        prev: RasterLayerEntity<Layer>
    ) async -> Layer? {
        if current.fingerPrint.source != prev.fingerPrint.source {
            await removeLayer(entity: prev)
            guard let scene, let newLayer = makeLayer(from: current.state) else { return nil }
            apply(state: current.state, to: newLayer)
            scene.addOperationalLayer(newLayer)
            return newLayer
        }
        apply(state: current.state, to: layer)
        return layer
    }

    override func removeLayer(entity: RasterLayerEntity<Layer>) async {
        guard let layer = entity.layer else { return }
        scene?.removeOperationalLayer(layer)
    }

    private func apply(state: RasterLayerState, to layer: Layer) {
        layer.opacity = Float(state.opacity)
        layer.isVisible = state.visible
    }

    private func makeLayer(from state: RasterLayerState) -> Layer? {
        switch state.source {
        case let .arcGisService(serviceUrl):
            guard let url = URL(string: serviceUrl) else { return nil }
            return ArcGISTiledLayer(url: url)
        case let .urlTemplate(template, _, _, _, _, scheme):
            if scheme == .TMS {
                NSLog("[MapConductor] ArcGIS RasterLayer: TMS scheme is not supported. id=%@", state.id)
                return nil
            }
            let converted = template
                .replacingOccurrences(of: "{z}", with: "{level}")
                .replacingOccurrences(of: "{x}", with: "{col}")
                .replacingOccurrences(of: "{y}", with: "{row}")
            return WebTiledLayer(urlTemplate: converted, subDomains: [])
        case .tileJson:
            NSLog("[MapConductor] ArcGIS RasterLayer: tileJson sources are not supported. id=%@", state.id)
            return nil
        }
    }
}
