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
}
