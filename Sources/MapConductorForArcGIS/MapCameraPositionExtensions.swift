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
    let finalHeading = (cameraHeadingOffset + 180).truncatingRemainder(dividingBy: 360)

    if cameraPitchOffset < 0.0 {
        return Camera(
            latitude: targetPoint.y,
            longitude: targetPoint.x,
            altitude: distance,
            heading: finalHeading,
            pitch: min(abs(cameraPitchOffset), arcGISMaxPitch),
            roll: 0
        )
    }

    let finalPitch = min(cameraPitchOffset, arcGISMaxPitch)
    let pitchRad = finalPitch * .pi / 180
    let altitude = distance * cos(pitchRad)
    let cameraCoordinates = calculateDestinationPoint(
        lat: targetPoint.y,
        lon: targetPoint.x,
        bearing: cameraHeadingOffset,
        distance: distance * sin(pitchRad)
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

    func toMapCameraPosition(
        logicalTiltHint: Double? = nil,
        visibleRegion: VisibleRegion? = nil,
        viewportSize: CGSize? = nil
    ) -> MapCameraPosition {
        let altitude = location.z ?? 0
        let width = viewportSize.map { Int($0.width) }
        let height = viewportSize.map { Int($0.height) }
        let logicalTilt = logicalTiltHint.map { $0 < 0.0 ? -abs(pitch) : pitch } ?? pitch
        let tiltForZoom = logicalTilt < 0.0 ? 0.0 : pitch

        // Camera.location is the eye, but MapCameraPosition.position is the target (the ground
        // point at screen center). For positive tilt the orbit camera sits behind the target by
        // distance * sin(pitch) — see calculateCameraForOrbitParameters — so shift forward along
        // the view heading to recover the target; otherwise a set→read→set cycle teleports the
        // target backward by that offset.
        let target: GeoPoint
        if logicalTilt >= 0.0, pitch > 0.01 {
            let pitchRad = min(pitch, arcGISMaxPitch) * .pi / 180
            let distance = altitude / max(cos(pitchRad), 0.05)
            target = calculateDestinationPoint(
                lat: location.y,
                lon: location.x,
                bearing: heading,
                distance: distance * sin(pitchRad)
            )
        } else {
            target = GeoPoint(latitude: location.y, longitude: location.x, altitude: 0)
        }

        return MapCameraPosition(
            position: GeoPoint(latitude: target.latitude, longitude: target.longitude, altitude: altitude),
            zoom: arcGISCameraConverter.altitudeToZoomLevel(altitude: altitude, latitude: target.latitude, tilt: tiltForZoom, viewportWidthPx: width, viewportHeightPx: height),
            bearing: ((heading.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360),
            tilt: logicalTilt,
            visibleRegion: visibleRegion
        )
    }
}
