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
    /// `x` / `y` をそのまま経度・緯度として読む。呼ぶ前に WGS84 であることを保証すること
    /// （2D の `MapView` 由来の点は ``projectedToWGS84()`` を挟む）。
    func toGeoPoint() -> GeoPoint {
        GeoPoint(latitude: y, longitude: x, altitude: z ?? 0)
    }

    /// WGS84（緯度経度）へ投影する。
    ///
    /// 2D の `MapView` はマップの空間参照（`Map(basemapStyle:)` の既定では Web メルカトル）で
    /// 座標を返すため、``toGeoPoint()`` でそのまま読むとメートル値を緯度経度として扱ってしまう。
    /// 3D の `SceneView` は元から WGS84 なのでこの変換は不要（no-op）。
    /// 空間参照が不明な点は変換できないためそのまま返す。
    func projectedToWGS84() -> Point {
        guard let spatialReference, spatialReference != .wgs84 else { return self }
        return GeometryEngine.project(self, into: .wgs84) ?? self
    }
}
