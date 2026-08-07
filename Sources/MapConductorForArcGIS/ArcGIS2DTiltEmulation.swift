import Foundation
import MapConductorCore

/// ArcGIS の 2D `MapView` 向けの tilt 擬似表現。
///
/// 2D `MapView` は `Viewpoint`（中心 + 縮尺 + 回転）ベースでカメラピッチを一切持てない。
/// 3D の `SceneView`（`ArcGISMapView`）は `calculateCameraForOrbitParameters` で実際に
/// ピッチできるが、2D では遠近感を作れないため、**カメラが見ている地表範囲**を幾何的に
/// 近似する方式を採る。
///
/// 見た目の傾き（遠近感）は `ArcGISMapView2D` が `MapView` 自体を `rotation3DEffect` で
/// 傾けて作る（react-for-leaflet が CSS `rotateX` で行うのと同じ方式）。ここが受け持つのは
/// **カメラ位置の付け替え**だけ:
///
/// - tilt >= 0: 指定位置は**ターゲット**（画面中心）でカメラが後方へ下がるだけなので、
///   中心もズームも変えない。傾きは見た目の変換だけで表現される。
/// - tilt < 0: 指定位置は**カメラ位置**で、ターゲットが進行方向（bearing）へ前進する。
///   前進量とズームオフセットは MapLibre / TomTom / Leaflet と同一の式・同一定数。
///
/// いずれの場合も、カメラの読み戻しでは論理 tilt をそのまま返す（`restoreLogicalCamera`）。
enum ArcGIS2DTiltEmulation {
    /// MapLibre / TomTom / Leaflet と同一値。プロバイダ間で挙動を揃えるため変えないこと。
    static let targetDistanceScale = 1.83
    static let zoomOffsetAtMaxTilt = -0.9

    /// 高度の算出にはプラットフォーム非依存の既定値（Google Maps 較正）を使う。
    ///
    /// `ArcGISZoomAltitudeConverter` の既定値（iOS 141_600_000 / Android 136_500_000）は
    /// **3D SceneView の実効画角**を合わせるための較正値で、画角を持たない 2D MapView には
    /// 当てはまらない。既定値を使うことで、シフト量が Android と厳密に一致する
    /// （TomTom / MapLibre の負tilt が 3 プラットフォームで一致しているのと同じ扱い）。
    private static let converter = ArcGISZoomAltitudeConverter(
        zoom0Altitude: ArcGISZoomAltitudeConverter.defaultZoom0Altitude
    )

    /// 論理カメラ → 実際に `Viewpoint` へ渡す中心・ズーム。
    ///
    /// tilt < 0 のときだけ中心を進行方向へ前進させ、ズームを引く。tilt >= 0 は入力のまま
    /// （`position` が**ターゲット**＝画面中心で、カメラが後方へ下がるだけのため）。
    /// サンプルの `TiltCameraDiagram` と同じ定義。
    static func shiftedCamera(for position: MapCameraPosition) -> (center: GeoPoint, zoom: Double) {
        let tiltAbsDeg = min(max(abs(position.tilt), 0.0), 60.0)

        guard position.tilt < 0 else {
            let center = GeoPoint(
                latitude: position.position.latitude,
                longitude: position.position.longitude,
                altitude: position.position.altitude ?? 0
            )
            return (center, position.zoom)
        }

        let zoom = position.zoom + zoomOffsetAtMaxTilt * (tiltAbsDeg / 60.0)
        let tiltAbsRad = tiltAbsDeg * .pi / 180.0
        let altitude = converter.zoomLevelToAltitude(
            zoomLevel: position.zoom,
            latitude: position.position.latitude,
            tilt: 0.0
        )
        let distanceForward = altitude * cos(tiltAbsRad) * tan(tiltAbsRad) * targetDistanceScale
        let target = Spherical.computeOffset(
            origin: position.position,
            distance: distanceForward,
            heading: position.bearing
        )
        return (target, zoom)
    }

    /// `Viewpoint` から読み戻した中心・ズームを論理カメラへ戻す。
    ///
    /// [shiftedCamera] の逆変換。tilt < 0 のときだけ中心とズームを巻き戻す。
    ///
    /// - Parameters:
    ///   - logicalTilt: 直近に要求した論理 tilt。
    ///   - bearing: 前進に使った方位（論理 bearing）。
    static func restoreLogicalCamera(
        center: GeoPoint,
        zoom: Double,
        bearing: Double,
        logicalTilt: Double
    ) -> (position: GeoPoint, zoom: Double) {
        let tiltAbsDeg = min(max(abs(logicalTilt), 0.0), 60.0)
        guard logicalTilt < 0, tiltAbsDeg > 0 else { return (center, zoom) }

        let originalZoom = zoom - zoomOffsetAtMaxTilt * (tiltAbsDeg / 60.0)
        let tiltAbsRad = tiltAbsDeg * .pi / 180.0
        let altitude = converter.zoomLevelToAltitude(
            zoomLevel: originalZoom,
            latitude: center.latitude,
            tilt: 0.0
        )
        let distanceBackward = altitude * cos(tiltAbsRad) * tan(tiltAbsRad) * targetDistanceScale
        let originalPosition = Spherical.computeOffset(
            origin: center,
            distance: distanceBackward,
            heading: bearing + 180.0
        )
        return (originalPosition, originalZoom)
    }
}
