import ArcGIS
import Combine
import CoreGraphics
import Foundation
import MapConductorCore
import Swift
import SwiftUI
import UIKit
import _Concurrency
import _StringProcessing
import _SwiftConcurrencyShims
public protocol ArcGISMapDesignTypeProtocol : MapConductorCore.MapDesignTypeProtocol where Self.Identifier == Swift.String {
  var elevationSources: [Swift.String] { get }
}
public typealias ArcGISMapDesignType = any MapConductorForArcGIS.ArcGISMapDesignTypeProtocol
public typealias ArcGISDesignTypeChangeHandler = (MapConductorForArcGIS.ArcGISMapDesignType) -> Swift.Void
public struct ArcGISDesign : MapConductorForArcGIS.ArcGISMapDesignTypeProtocol, Swift.Hashable {
  public let id: Swift.String
  public let elevationSources: [Swift.String]
  public let attributionRules: [MapConductorCore.AttributionRule]
  public init(id: Swift.String, elevationSources: [Swift.String] = [], attributionRules: [MapConductorCore.AttributionRule] = [])
  public func getValue() -> Swift.String
  public func withElevationSources(_ sources: [Swift.String]) -> MapConductorForArcGIS.ArcGISDesign
  public static let Streets: MapConductorForArcGIS.ArcGISDesign
  public static let Imagery: MapConductorForArcGIS.ArcGISDesign
  public static let ImageryStandard: MapConductorForArcGIS.ArcGISDesign
  public static let ImageryLabels: MapConductorForArcGIS.ArcGISDesign
  public static let LightGray: MapConductorForArcGIS.ArcGISDesign
  public static let LightGrayBase: MapConductorForArcGIS.ArcGISDesign
  public static let LightGrayLabels: MapConductorForArcGIS.ArcGISDesign
  public static let DarkGray: MapConductorForArcGIS.ArcGISDesign
  public static let DarkGrayBase: MapConductorForArcGIS.ArcGISDesign
  public static let DarkGrayLabels: MapConductorForArcGIS.ArcGISDesign
  public static let Navigation: MapConductorForArcGIS.ArcGISDesign
  public static let NavigationNight: MapConductorForArcGIS.ArcGISDesign
  public static let StreetsNight: MapConductorForArcGIS.ArcGISDesign
  public static let StreetsRelief: MapConductorForArcGIS.ArcGISDesign
  public static let Topographic: MapConductorForArcGIS.ArcGISDesign
  public static let Oceans: MapConductorForArcGIS.ArcGISDesign
  public static let OceansBase: MapConductorForArcGIS.ArcGISDesign
  public static let OceansLabels: MapConductorForArcGIS.ArcGISDesign
  public static let Terrain: MapConductorForArcGIS.ArcGISDesign
  public static let TerrainBase: MapConductorForArcGIS.ArcGISDesign
  public static let TerrainDetail: MapConductorForArcGIS.ArcGISDesign
  public static let Community: MapConductorForArcGIS.ArcGISDesign
  public static let ChartedTerritory: MapConductorForArcGIS.ArcGISDesign
  public static let ColoredPencil: MapConductorForArcGIS.ArcGISDesign
  public static let Nova: MapConductorForArcGIS.ArcGISDesign
  public static let ModernAntique: MapConductorForArcGIS.ArcGISDesign
  public static let Midcentury: MapConductorForArcGIS.ArcGISDesign
  public static let Newspaper: MapConductorForArcGIS.ArcGISDesign
  public static let HillshadeLight: MapConductorForArcGIS.ArcGISDesign
  public static let HillshadeDark: MapConductorForArcGIS.ArcGISDesign
  public static let StreetsReliefBase: MapConductorForArcGIS.ArcGISDesign
  public static let TopographicBase: MapConductorForArcGIS.ArcGISDesign
  public static let ChartedTerritoryBase: MapConductorForArcGIS.ArcGISDesign
  public static let ModernAntiqueBase: MapConductorForArcGIS.ArcGISDesign
  public static let HumanGeography: MapConductorForArcGIS.ArcGISDesign
  public static let HumanGeographyBase: MapConductorForArcGIS.ArcGISDesign
  public static let HumanGeographyDetail: MapConductorForArcGIS.ArcGISDesign
  public static let HumanGeographyLabels: MapConductorForArcGIS.ArcGISDesign
  public static let HumanGeographyDark: MapConductorForArcGIS.ArcGISDesign
  public static let HumanGeographyDarkBase: MapConductorForArcGIS.ArcGISDesign
  public static let HumanGeographyDarkDetail: MapConductorForArcGIS.ArcGISDesign
  public static let HumanGeographyDarkLabels: MapConductorForArcGIS.ArcGISDesign
  public static let Outdoor: MapConductorForArcGIS.ArcGISDesign
  public static let OsmStandard: MapConductorForArcGIS.ArcGISDesign
  public static let OsmStandardRelief: MapConductorForArcGIS.ArcGISDesign
  public static let OsmStandardReliefBase: MapConductorForArcGIS.ArcGISDesign
  public static let OsmStreets: MapConductorForArcGIS.ArcGISDesign
  public static let OsmStreetsRelief: MapConductorForArcGIS.ArcGISDesign
  public static let OsmLightGray: MapConductorForArcGIS.ArcGISDesign
  public static let OsmLightGrayBase: MapConductorForArcGIS.ArcGISDesign
  public static let OsmLightGrayLabels: MapConductorForArcGIS.ArcGISDesign
  public static let OsmDarkGray: MapConductorForArcGIS.ArcGISDesign
  public static let OsmDarkGrayBase: MapConductorForArcGIS.ArcGISDesign
  public static let OsmDarkGrayLabels: MapConductorForArcGIS.ArcGISDesign
  public static let OsmStreetsReliefBase: MapConductorForArcGIS.ArcGISDesign
  public static let OsmBlueprint: MapConductorForArcGIS.ArcGISDesign
  public static let OsmHybrid: MapConductorForArcGIS.ArcGISDesign
  public static let OsmHybridDetail: MapConductorForArcGIS.ArcGISDesign
  public static let OsmNavigation: MapConductorForArcGIS.ArcGISDesign
  public static let OsmNavigationDark: MapConductorForArcGIS.ArcGISDesign
  public static func Create(id: Swift.String, sources: [Swift.String] = []) -> MapConductorForArcGIS.ArcGISDesign
  public static func toBasemapStyle(_ designType: MapConductorForArcGIS.ArcGISMapDesignType) -> ArcGIS.Basemap.Style
  public static func == (a: MapConductorForArcGIS.ArcGISDesign, b: MapConductorForArcGIS.ArcGISDesign) -> Swift.Bool
  public typealias Identifier = Swift.String
  public func hash(into hasher: inout Swift.Hasher)
  public var hashValue: Swift.Int {
    get
  }
}
@_Concurrency.MainActor @preconcurrency public struct ArcGISMapView : SwiftUICore.View {
  @_Concurrency.MainActor @preconcurrency public init(state: MapConductorForArcGIS.ArcGISMapViewState, cameraRestriction: MapConductorCore.CameraRestriction? = nil, onMapLoaded: MapConductorCore.OnMapLoadedHandler<MapConductorForArcGIS.ArcGISMapViewState>? = nil, onMapClick: MapConductorCore.OnMapEventHandler? = nil, onMapLongClick: MapConductorCore.OnMapEventHandler? = nil, onCameraMoveStart: MapConductorCore.OnCameraMoveHandler? = nil, onCameraMove: MapConductorCore.OnCameraMoveHandler? = nil, onCameraMoveEnd: MapConductorCore.OnCameraMoveHandler? = nil, sdkInitialize: (() -> Swift.Void)? = nil, @MapConductorCore.MapViewContentBuilder content: @escaping () -> MapConductorCore.MapViewContent = { MapViewContent() })
  @_Concurrency.MainActor @preconcurrency public var body: some SwiftUICore.View {
    get
  }
  public typealias Body = @_opaqueReturnTypeOf("$s21MapConductorForArcGIS0D10GISMapViewV4bodyQrvp", 0) __
}
@_Concurrency.MainActor @preconcurrency public struct ArcGISMapView2D : SwiftUICore.View {
  @_Concurrency.MainActor @preconcurrency public init(state: MapConductorForArcGIS.ArcGISMapViewState, cameraRestriction: MapConductorCore.CameraRestriction? = nil, onMapLoaded: MapConductorCore.OnMapLoadedHandler<MapConductorForArcGIS.ArcGISMapViewState>? = nil, onMapClick: MapConductorCore.OnMapEventHandler? = nil, onMapLongClick: MapConductorCore.OnMapEventHandler? = nil, onCameraMoveStart: MapConductorCore.OnCameraMoveHandler? = nil, onCameraMove: MapConductorCore.OnCameraMoveHandler? = nil, onCameraMoveEnd: MapConductorCore.OnCameraMoveHandler? = nil, sdkInitialize: (() -> Swift.Void)? = nil, @MapConductorCore.MapViewContentBuilder content: @escaping () -> MapConductorCore.MapViewContent = { MapViewContent() })
  @_Concurrency.MainActor @preconcurrency public var body: some SwiftUICore.View {
    get
  }
  public typealias Body = @_opaqueReturnTypeOf("$s21MapConductorForArcGIS0D12GISMapView2DV4bodyQrvp", 0) __
}
@_hasMissingDesignatedInitializers final public class ArcGISSceneContainer {
  final public let scene: ArcGIS.Scene
  final public let graphicsOverlays: [ArcGIS.GraphicsOverlay]
  @objc deinit
}
@_hasMissingDesignatedInitializers final public class ArcGISMapContainer2D {
  final public let map: ArcGIS.Map
  final public let graphicsOverlays: [ArcGIS.GraphicsOverlay]
  @objc deinit
}
@_hasMissingDesignatedInitializers final public class ArcGISMapView2DHolder : MapConductorCore.MapViewHolderProtocol {
  final public let mapView: MapConductorForArcGIS.ArcGISMapContainer2D
  final public let map: ArcGIS.Map
  final public func toScreenOffset(position: any MapConductorCore.GeoPointProtocol) -> CoreFoundation.CGPoint?
  final public func fromScreenOffset(offset: CoreFoundation.CGPoint) async -> MapConductorCore.GeoPoint?
  final public func fromScreenOffsetSync(offset: CoreFoundation.CGPoint) -> MapConductorCore.GeoPoint?
  public typealias ActualMap = ArcGIS.Map
  public typealias ActualMapView = MapConductorForArcGIS.ArcGISMapContainer2D
  @objc deinit
}
@_hasMissingDesignatedInitializers final public class ArcGISMapViewHolder : MapConductorCore.MapViewHolderProtocol {
  final public let mapView: MapConductorForArcGIS.ArcGISSceneContainer
  final public let map: ArcGIS.Scene
  final public func toScreenOffset(position: any MapConductorCore.GeoPointProtocol) -> CoreFoundation.CGPoint?
  final public func fromScreenOffset(offset: CoreFoundation.CGPoint) async -> MapConductorCore.GeoPoint?
  final public func fromScreenOffsetSync(offset: CoreFoundation.CGPoint) -> MapConductorCore.GeoPoint?
  public typealias ActualMap = ArcGIS.Scene
  public typealias ActualMapView = MapConductorForArcGIS.ArcGISSceneContainer
  @objc deinit
}
final public class ArcGISMapViewState : MapConductorCore.MapViewState<MapConductorForArcGIS.ArcGISMapDesignType> {
  final public var sceneViewHolder: MapConductorForArcGIS.ArcGISMapViewHolder? {
    get
  }
  final public var mapView2DHolder: MapConductorForArcGIS.ArcGISMapView2DHolder? {
    get
  }
  override final public var id: Swift.String {
    get
  }
  override final public var cameraPosition: MapConductorCore.MapCameraPosition {
    get
  }
  override final public var mapDesignType: MapConductorForArcGIS.ArcGISMapDesignType {
    get
    set
  }
  override final public var uiSettings: MapConductorCore.MapUISettings {
    get
    set
  }
  public init(id: Swift.String, mapDesignType: MapConductorForArcGIS.ArcGISMapDesignType = ArcGISDesign.Streets, cameraPosition: MapConductorCore.MapCameraPosition = .Default, uiSettings: MapConductorCore.MapUISettings = MapUISettings())
  convenience public init(mapDesignType: MapConductorForArcGIS.ArcGISMapDesignType = ArcGISDesign.Streets, cameraPosition: MapConductorCore.MapCameraPosition = .Default, uiSettings: MapConductorCore.MapUISettings = MapUISettings())
  override final public func moveCameraTo(cameraPosition: MapConductorCore.MapCameraPosition, durationMillis: MapConductorCore.Long? = 0)
  override final public func fitBounds(bounds: MapConductorCore.GeoRectBounds, padding: Swift.Int)
  override final public func moveCameraTo(position: MapConductorCore.GeoPoint, durationMillis: MapConductorCore.Long? = 0)
  override final public func getMapViewHolder() -> MapConductorCore.AnyMapViewHolder?
  @objc deinit
}
public typealias ArcGISActualMarker = ArcGIS.Graphic
public typealias ArcGISActualCircle = ArcGIS.Graphic
public typealias ArcGISActualPolyline = ArcGIS.Graphic
public typealias ArcGISActualPolygon = ArcGIS.Graphic
public typealias ArcGISActualRasterLayer = ArcGIS.Layer
public typealias ArcGISActualGroundImage = MapConductorForArcGIS.ArcGISGroundImageHandle
extension MapConductorCore.GeoPointProtocol {
  public func toArcGISPoint(spatialReference: ArcGIS.SpatialReference? = nil) -> ArcGIS.Point
}
extension MapConductorCore.GeoPoint {
  public static func fromLatLongAltitude(latitude: Swift.Double, longitude: Swift.Double, altitude: Swift.Double) -> MapConductorCore.GeoPoint
  public static func fromLongLat(longitude: Swift.Double, latitude: Swift.Double, altitude: Swift.Double = 0) -> MapConductorCore.GeoPoint
}
extension ArcGIS.Point {
  final public func toGeoPoint() -> MapConductorCore.GeoPoint
  final public func projectedToWGS84() -> ArcGIS.Point
}
extension MapConductorCore.MapCameraPosition {
  final public func altitudeForArcGIS() -> Swift.Double
  final public func toArcGISCamera(viewportSize: CoreFoundation.CGSize? = nil) -> ArcGIS.Camera
}
public func calculateDestinationPoint(lat: Swift.Double, lon: Swift.Double, bearing: Swift.Double, distance: Swift.Double) -> MapConductorCore.GeoPoint
public func calculateCameraForOrbitParameters(targetPoint: ArcGIS.Point, distance: Swift.Double, cameraHeadingOffset: Swift.Double, cameraPitchOffset: Swift.Double) -> ArcGIS.Camera
extension ArcGIS.Camera {
  public func getZoomLevel() -> Swift.Double
  public func toMapCameraPosition(logicalTiltHint: Swift.Double? = nil, visibleRegion: MapConductorCore.VisibleRegion? = nil, viewportSize: CoreFoundation.CGSize? = nil) -> MapConductorCore.MapCameraPosition
}
final public class ArcGISZoomAltitudeConverter : MapConductorCore.ZoomAltitudeConverterProtocol {
  public static let arcGISOptimizedZoom0Altitude: Swift.Double
  final public let zoom0Altitude: Swift.Double
  public init(zoom0Altitude: Swift.Double = ArcGISZoomAltitudeConverter.arcGISOptimizedZoom0Altitude)
  final public func zoomLevelToAltitude(zoomLevel: Swift.Double, latitude: Swift.Double, tilt: Swift.Double) -> Swift.Double
  final public func altitudeToZoomLevel(altitude: Swift.Double, latitude: Swift.Double, tilt: Swift.Double) -> Swift.Double
  final public func zoomLevelToAltitude(zoomLevel: Swift.Double, latitude: Swift.Double, tilt: Swift.Double, viewportWidthPx: Swift.Int?, viewportHeightPx: Swift.Int?) -> Swift.Double
  final public func altitudeToZoomLevel(altitude: Swift.Double, latitude: Swift.Double, tilt: Swift.Double, viewportWidthPx: Swift.Int?, viewportHeightPx: Swift.Int?) -> Swift.Double
  final public func zoomLevelToDistance(zoomLevel: Swift.Double, latitude: Swift.Double, viewportWidthPx: Swift.Int? = nil, viewportHeightPx: Swift.Int? = nil) -> Swift.Double
  @objc deinit
}
public func arcGISApiKeyInitialize(apiKey: Swift.String) -> Swift.Bool
public func arcGISOAuthApplicationInitialize(portalUrl: Swift.String, clientId: Swift.String, clientSecret: Swift.String, tokenExpirationMinutes: Swift.Int = 0) async -> Swift.Bool
public func arcGISOAuthUserInitialize(portalUrl: Swift.String, clientId: Swift.String, redirectUrl: Swift.String) async -> Swift.Bool
public func ArcGISOAuthHybridInitialize(portalUrl: Swift.String, redirectUrl: Swift.String, clientId: Swift.String, clientSecret: Swift.String? = nil) async -> Swift.Bool
public struct ArcGISGroundImageHandle {
}
extension MapConductorForArcGIS.ArcGISMapView : Swift.Sendable {}
extension MapConductorForArcGIS.ArcGISMapView2D : Swift.Sendable {}
