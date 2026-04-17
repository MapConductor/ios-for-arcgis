import ArcGIS
import Foundation
import MapConductorCore

private let arcGISCameraConverter = ArcGISZoomAltitudeConverter()
private let earthMeanRadiusMeters = 6_371_000.0
private let arcGISMaxPitch = 90.0

public extension MapCameraPosition {
    func altitudeForArcGIS() -> Double {
        arcGISCameraConverter.zoomLevelToAltitude(zoomLevel: zoom, latitude: position.latitude, tilt: tilt)
    }

    func toArcGISCamera(viewportSize: CGSize? = nil) -> Camera {
        let targetPoint = position.toArcGISPoint(spatialReference: .wgs84)
        let width = viewportSize.map { Int($0.width) }
        let height = viewportSize.map { Int($0.height) }
        let distance = arcGISCameraConverter.zoomLevelToDistance(
            zoomLevel: zoom,
            latitude: position.latitude,
            viewportWidthPx: width,
            viewportHeightPx: height
        )
        return calculateCameraForOrbitParameters(
            targetPoint: targetPoint,
            distance: distance,
            cameraHeadingOffset: bearing + 180,
            cameraPitchOffset: tilt
        )
    }
}

public func calculateDestinationPoint(lat: Double, lon: Double, bearing: Double, distance: Double) -> GeoPoint {
    let latRad = lat * .pi / 180
    let lonRad = lon * .pi / 180
    let bearingRad = bearing * .pi / 180
    let angularDistance = distance / earthMeanRadiusMeters

    let destLatRad = asin(sin(latRad) * cos(angularDistance) + cos(latRad) * sin(angularDistance) * cos(bearingRad))
    var destLonRad = lonRad + atan2(
        sin(bearingRad) * sin(angularDistance) * cos(latRad),
        cos(angularDistance) - sin(latRad) * sin(destLatRad)
    )
    destLonRad = (destLonRad + 3 * .pi).truncatingRemainder(dividingBy: 2 * .pi) - .pi

    return GeoPoint(latitude: destLatRad * 180 / .pi, longitude: destLonRad * 180 / .pi, altitude: 0)
}

public func calculateCameraForOrbitParameters(
    targetPoint: Point,
    distance: Double,
    cameraHeadingOffset: Double,
    cameraPitchOffset: Double
) -> Camera {
    let finalPitch = max(0, min(cameraPitchOffset, arcGISMaxPitch))
    let pitchRad = finalPitch * .pi / 180
    let altitude = distance * cos(pitchRad)
    let finalHeading = (cameraHeadingOffset + 180).truncatingRemainder(dividingBy: 360)
    let horizontalDistance = distance * sin(pitchRad)
    let cameraCoordinates = calculateDestinationPoint(
        lat: targetPoint.y,
        lon: targetPoint.x,
        bearing: cameraHeadingOffset,
        distance: horizontalDistance
    )

    return Camera(
        latitude: cameraCoordinates.latitude,
        longitude: cameraCoordinates.longitude,
        altitude: altitude,
        heading: finalHeading,
        pitch: finalPitch,
        roll: 0
    )
}

public extension Camera {
    func getZoomLevel() -> Double {
        arcGISCameraConverter.altitudeToZoomLevel(altitude: location.z ?? 0, latitude: location.y, tilt: pitch)
    }

    func toMapCameraPosition(visibleRegion: VisibleRegion? = nil) -> MapCameraPosition {
        let altitude = location.z ?? 0
        return MapCameraPosition(
            position: GeoPoint(latitude: location.y, longitude: location.x, altitude: altitude),
            zoom: arcGISCameraConverter.altitudeToZoomLevel(altitude: altitude, latitude: location.y, tilt: pitch),
            bearing: ((heading.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360),
            tilt: pitch,
            visibleRegion: visibleRegion
        )
    }
}
