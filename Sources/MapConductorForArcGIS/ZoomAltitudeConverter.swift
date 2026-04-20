import Foundation
import MapConductorCore

public final class ArcGISZoomAltitudeConverter: ZoomAltitudeConverterProtocol {
    public static let arcGISOptimizedZoom0Altitude = 124_000_000.0
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
