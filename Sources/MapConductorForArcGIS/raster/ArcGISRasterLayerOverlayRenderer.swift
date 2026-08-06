import ArcGIS
import Foundation
import MapConductorCore

@MainActor
final class ArcGISRasterLayerOverlayRenderer: AbstractRasterLayerOverlayRenderer<Layer> {
    private let addLayer: (Layer) -> Void
    private let removeLayerFn: (Layer) -> Void

    convenience init(scene: ArcGIS.Scene) {
        self.init(
            addLayer: { [weak scene] layer in scene?.addOperationalLayer(layer) },
            removeLayer: { [weak scene] layer in scene?.removeOperationalLayer(layer) }
        )
    }

    convenience init(map: ArcGIS.Map) {
        self.init(
            addLayer: { [weak map] layer in map?.addOperationalLayer(layer) },
            removeLayer: { [weak map] layer in map?.removeOperationalLayer(layer) }
        )
    }

    init(addLayer: @escaping (Layer) -> Void, removeLayer: @escaping (Layer) -> Void) {
        self.addLayer = addLayer
        self.removeLayerFn = removeLayer
        super.init()
    }

    override func createLayer(state: RasterLayerState) async -> Layer? {
        RasterHeaderRuleSet.warnUnsupported(provider: "ArcGIS", state: state)
        guard let layer = makeLayer(from: state) else { return nil }
        apply(state: state, to: layer)
        if state.debug {
            NSLog("[MapConductor] RasterLayer debug mode: id=%@", state.id)
        }
        addLayer(layer)
        return layer
    }

    override func updateLayerProperties(
        layer: Layer,
        current: RasterLayerEntity<Layer>,
        prev: RasterLayerEntity<Layer>
    ) async -> Layer? {
        if current.fingerPrint.source != prev.fingerPrint.source {
            await removeLayer(entity: prev)
            guard let newLayer = makeLayer(from: current.state) else { return nil }
            apply(state: current.state, to: newLayer)
            if current.state.debug {
                NSLog("[MapConductor] RasterLayer debug mode: id=%@", current.state.id)
            }
            addLayer(newLayer)
            return newLayer
        }
        if current.fingerPrint.debug != prev.fingerPrint.debug && current.state.debug {
            NSLog("[MapConductor] RasterLayer debug mode: id=%@", current.state.id)
        }
        apply(state: current.state, to: layer)
        return layer
    }

    override func removeLayer(entity: RasterLayerEntity<Layer>) async {
        guard let layer = entity.layer else { return }
        removeLayerFn(layer)
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
