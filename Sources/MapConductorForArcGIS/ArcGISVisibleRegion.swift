import CoreGraphics
import Foundation
@_spi(MapConductorDriver) import MapConductorCore

/// カメラ位置とビューポートサイズから可視領域を解析的に求める。
///
/// ArcGIS の 2D（MapView）と 3D（SceneView）で共通に使う。以前は 3D 側の
/// `ArcGISMapViewModel` に private static として置かれていたが、2D でも
/// マーカークラスタリングに `visibleRegion.bounds` が要るため切り出した。
///
/// クラスタリングは `visibleRegion.bounds` だけを見るので、投影の厳密さより
/// 2D/3D で同じ値になることを優先している。
func arcGISComputeVisibleRegion(for position: MapCameraPosition, viewportSize: CGSize?) -> VisibleRegion? {
    guard let size = viewportSize, size.width > 0, size.height > 0 else { return nil }

    let center = GeoPoint.from(position: position.position)
    let latRad = center.latitude * .pi / 180
    // θ: 画面の上が指す方位。bearing は「地図を時計回りに回す量」なので、
    // 画面の上が指す方位はその符号反転（= カメラの heading）になる。
    let θ = CameraBearing.toNativeHeading(position.bearing) * .pi / 180

    // Web-Mercator ground resolution: metres per pixel at this zoom and latitude
    let metersPerPixel = (2 * .pi * 6_371_000.0 * cos(latRad)) / (256.0 * pow(2.0, position.zoom))

    let halfW = Double(size.width) / 2
    let halfH = Double(size.height) / 2

    // Convert screen offset (sx right, sy down) → geographic offset (east, north in metres)
    // geo_east  =  (sx·cos θ − sy·sin θ) · m/px
    // geo_north = (−sx·sin θ − sy·cos θ) · m/px
    func cornerGeo(sxPx: Double, syPx: Double) -> GeoPoint {
        let eastM  = ( sxPx * cos(θ) - syPx * sin(θ)) * metersPerPixel
        let northM = (-sxPx * sin(θ) - syPx * cos(θ)) * metersPerPixel
        let dLat = northM / 111_000.0
        let dLng = eastM  / (111_000.0 * cos(latRad))
        return GeoPoint(latitude: center.latitude + dLat, longitude: center.longitude + dLng)
    }

    // Screen corners: sx = signed x from centre, sy = signed y from centre (down positive)
    let nl = cornerGeo(sxPx: -halfW, syPx: +halfH)  // bottom-left  → nearLeft
    let nr = cornerGeo(sxPx: +halfW, syPx: +halfH)  // bottom-right → nearRight
    let fl = cornerGeo(sxPx: -halfW, syPx: -halfH)  // top-left     → farLeft
    let fr = cornerGeo(sxPx: +halfW, syPx: -halfH)  // top-right    → farRight

    let bounds = GeoRectBounds()
    [nl, nr, fl, fr].forEach { bounds.extend(point: $0) }

    return VisibleRegion(bounds: bounds, nearLeft: nl, nearRight: nr, farLeft: fl, farRight: fr)
}
