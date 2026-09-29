import ArcGIS
import Foundation
import MapConductorCore

@MainActor
final class ArcGISRasterLayerController: RasterLayerController<Layer, ArcGISRasterLayerOverlayRenderer> {
    init(scene: ArcGIS.Scene) {
        super.init(rasterLayerManager: RasterLayerManager<Layer>(), renderer: ArcGISRasterLayerOverlayRenderer(scene: scene))
    }

    init(map: ArcGIS.Map) {
        super.init(rasterLayerManager: RasterLayerManager<Layer>(), renderer: ArcGISRasterLayerOverlayRenderer(map: map))
    }

    func refreshDirectLayers() async {
        // In a SceneView, CustomTiledLayer can retain its initial tile set
        // after the camera moves. Recreate only in-process layers once the
        // existing camera debounce fires, so the final viewport is requested
        // without reintroducing the local HTTP hop.
        let entities = rasterLayerManager.allEntities()
            .filter { renderer.isDirectLocalLayer(state: $0.state) }
            .sorted { $0.state.zIndex < $1.state.zIndex }
        for entity in entities {
            await renderer.removeLayer(entity: entity)
            guard let layer = await renderer.createLayer(state: entity.state) else { continue }
            rasterLayerManager.registerEntity(RasterLayerEntity(layer: layer, state: entity.state))
        }
        renderer.directLayersRebuilt()
    }
}
