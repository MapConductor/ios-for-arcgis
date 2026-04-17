import ArcGIS
import MapConductorCore

public extension GeoPointProtocol {
    func toArcGISPoint(spatialReference: SpatialReference? = nil) -> Point {
        Point(x: longitude, y: latitude, z: altitude, spatialReference: spatialReference)
    }
}

public extension GeoPoint {
    static func fromLatLongAltitude(latitude: Double, longitude: Double, altitude: Double) -> GeoPoint {
        GeoPoint(latitude: latitude, longitude: longitude, altitude: altitude)
    }

    static func fromLongLat(longitude: Double, latitude: Double, altitude: Double = 0) -> GeoPoint {
        GeoPoint(latitude: latitude, longitude: longitude, altitude: altitude)
    }
}

public extension Point {
    func toGeoPoint() -> GeoPoint {
        GeoPoint(latitude: y, longitude: x, altitude: z ?? 0)
    }
}
