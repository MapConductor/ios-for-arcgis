import ArcGIS
import MapConductorCore

public struct ArcGISGroundImageHandle {
    let routeId: String
    let generation: Int
    let cacheKey: String
    let tileProvider: GroundImageTileProvider
    let layer: WebTiledLayer
}
