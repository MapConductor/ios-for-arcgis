import Foundation
import MapConductorCore

public final class ArcGISZoomAltitudeConverter: ZoomAltitudeConverterProtocol {
    /// ズーム 0 のときのカメラ高度（``referenceHeightPoints`` のビューポート基準）。
    ///
    /// SceneView は垂直方向の画角が固定なので、見える地表の高さは `2 * altitude * tan(FOV/2)` に
    /// 比例する。Google Maps のズームは「ビューポートの高さ × 1 ピクセルあたりの地表距離」で
    /// 決まるため、この定数は実質「ArcGIS SceneView の実効垂直画角」の較正値になる。
    ///
    /// android-sdk / react-sdk は 136_500_000（＝実効画角 45.0°）を使っており、Android では
    /// それで Google Maps と一致する。iOS の ArcGIS Maps SDK for Swift は同じ高度でも
    /// Android より狭い範囲しか映らない（実効画角およそ 43°）ため、この値だけプラットフォーム
    /// 固有になる。ズーム ⇄ 高度の式そのものは 3 プラットフォームで同一。
    ///
    /// 較正方法: Camera Sync Test で Google Maps と ArcGIS 3D を並べ、同じ
    /// `MapCameraPosition` を与えて参照矩形の描画サイズを実機（iPad Pro 11"）で比較する。
    /// 旧値 136_500_000 では ArcGIS 側が 4〜7% 寄りすぎていた。
    ///
    /// なお ArcGIS 3D は球体を透視投影するため、Google（Web メルカトル）との差はズームと
    /// 緯度でわずかに変わり、定数 1 つで全域を完全一致させることはできない（低ズームの広域ほど
    /// 球面の影響が出る）。この値は歪みの小さい高ズーム側（緯度 21°/ズーム 9.5 で誤差 0.1% 以内）
    /// を優先して選んであり、広域側（緯度 65°/ズーム 5〜6）では 2% ほどの差が残る。
    public static let arcGISOptimizedZoom0Altitude = 141_600_000.0

    // Reference map view height in points, calibrated to match iPhone 16 Pro.
    // Altitude scales linearly with viewport height: altitude = zoom0Altitude * H / referenceHeightPoints.
    private static let referenceHeightPoints = 720.0

    public let zoom0Altitude: Double
    private let zoomFactor = 2.0
    private let minZoomLevel = 0.0
    private let maxZoomLevel = 22.0
    private let minAltitude = 100.0
    private let maxAltitude = 50_000_000.0
    private let minCosLat = 0.01
    private let minCosTilt = 0.05

    public init(zoom0Altitude: Double = ArcGISZoomAltitudeConverter.arcGISOptimizedZoom0Altitude) {
        self.zoom0Altitude = zoom0Altitude
    }

    public func zoomLevelToAltitude(zoomLevel: Double, latitude: Double, tilt: Double) -> Double {
        zoomLevelToAltitude(zoomLevel: zoomLevel, latitude: latitude, tilt: tilt, viewportWidthPx: nil, viewportHeightPx: nil)
    }

    public func altitudeToZoomLevel(altitude: Double, latitude: Double, tilt: Double) -> Double {
        altitudeToZoomLevel(altitude: altitude, latitude: latitude, tilt: tilt, viewportWidthPx: nil, viewportHeightPx: nil)
    }

    public func zoomLevelToAltitude(
        zoomLevel: Double,
        latitude: Double,
        tilt: Double,
        viewportWidthPx: Int?,
        viewportHeightPx: Int?
    ) -> Double {
        let clampedZoom = max(minZoomLevel, min(zoomLevel, maxZoomLevel))
        let distance = (resolveZoom0Altitude(viewportHeightPx: viewportHeightPx) * cosLatitudeFactor(latitude)) / pow(zoomFactor, clampedZoom)
        let altitude = distance * cosTiltFactor(tilt)
        return max(minAltitude, min(altitude, maxAltitude))
    }

    public func altitudeToZoomLevel(
        altitude: Double,
        latitude: Double,
        tilt: Double,
        viewportWidthPx: Int?,
        viewportHeightPx: Int?
    ) -> Double {
        let clampedAltitude = max(minAltitude, min(altitude, maxAltitude))
        let distance = clampedAltitude / cosTiltFactor(tilt)
        let zoom = log2((resolveZoom0Altitude(viewportHeightPx: viewportHeightPx) * cosLatitudeFactor(latitude)) / distance)
        return max(minZoomLevel, min(zoom, maxZoomLevel))
    }

    public func zoomLevelToDistance(
        zoomLevel: Double,
        latitude: Double,
        viewportWidthPx: Int? = nil,
        viewportHeightPx: Int? = nil
    ) -> Double {
        let clampedZoom = max(minZoomLevel, min(zoomLevel, maxZoomLevel))
        let distance = (resolveZoom0Altitude(viewportHeightPx: viewportHeightPx) * cosLatitudeFactor(latitude)) / pow(zoomFactor, clampedZoom)
        return max(minAltitude, min(distance, maxAltitude))
    }

    private func resolveZoom0Altitude(viewportHeightPx: Int?) -> Double {
        guard let height = viewportHeightPx, height > 0 else { return zoom0Altitude }
        return zoom0Altitude * Double(height) / Self.referenceHeightPoints
    }

    private func cosLatitudeFactor(_ latitude: Double) -> Double {
        max(minCosLat, cos(latitude * .pi / 180))
    }

    private func cosTiltFactor(_ tilt: Double) -> Double {
        max(minCosTilt, cos(tilt * .pi / 180))
    }
}
