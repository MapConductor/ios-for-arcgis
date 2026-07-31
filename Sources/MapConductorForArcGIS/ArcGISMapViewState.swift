import Combine
import Foundation
import MapConductorCore

public final class ArcGISMapViewState: MapViewState<ArcGISMapDesignType> {
    private let stateId: String

    @Published private var _cameraPosition: MapCameraPosition
    @Published private var _mapDesignType: ArcGISMapDesignType
    @Published private var _uiSettings: MapUISettings

    private var controller: ArcGISMapViewController?

    /// Provider-typed holder while the 3D `ArcGISMapView` (SceneView) is attached; nil in 2D mode.
    public private(set) var sceneViewHolder: ArcGISMapViewHolder?

    /// Provider-typed holder while the 2D `ArcGISMapView2D` (MapView) is attached; nil in 3D mode.
    public private(set) var mapView2DHolder: ArcGISMapView2DHolder?

    public override var id: String { stateId }
    public override var cameraPosition: MapCameraPosition { _cameraPosition }

    public override var mapDesignType: ArcGISMapDesignType {
        get { _mapDesignType }
        set {
            _mapDesignType = newValue
            controller?.setMapDesignType(newValue)
        }
    }

    public override var uiSettings: MapUISettings {
        get { _uiSettings }
        set { _uiSettings = newValue }
    }

    public init(
        id: String,
        mapDesignType: ArcGISMapDesignType = ArcGISDesign.Streets,
        cameraPosition: MapCameraPosition = .Default,
        uiSettings: MapUISettings = MapUISettings()
    ) {
        self.stateId = id
        self._mapDesignType = mapDesignType
        self._cameraPosition = cameraPosition
        self._uiSettings = uiSettings
        super.init()
    }

    public convenience init(
        mapDesignType: ArcGISMapDesignType = ArcGISDesign.Streets,
        cameraPosition: MapCameraPosition = .Default,
        uiSettings: MapUISettings = MapUISettings()
    ) {
        self.init(id: UUID().uuidString, mapDesignType: mapDesignType, cameraPosition: cameraPosition, uiSettings: uiSettings)
    }

    public override func moveCameraTo(cameraPosition: MapCameraPosition, durationMillis: Long? = 0) {
        let resolved = resolveCameraPosition(cameraPosition)
        if let controller {
            if let durationMillis, durationMillis > 0 {
                controller.animateCamera(position: resolved, duration: durationMillis)
            } else {
                controller.moveCamera(position: resolved)
            }
        } else {
            _cameraPosition = resolved
        }
    }

    public override func fitBounds(bounds: GeoRectBounds, padding: Int) {
        controller?.fitBounds(bounds: bounds, padding: padding)
    }

    public override func moveCameraTo(position: GeoPoint, durationMillis: Long? = 0) {
        moveCameraTo(cameraPosition: cameraPosition.copy(position: position), durationMillis: durationMillis)
    }

    public override func getMapViewHolder() -> AnyMapViewHolder? {
        if let sceneViewHolder { return AnyMapViewHolder(sceneViewHolder) }
        if let mapView2DHolder { return AnyMapViewHolder(mapView2DHolder) }
        return nil
    }

    func setController(_ controller: ArcGISMapViewController?) {
        self.controller = controller
        if let controller {
            // setMapDesignType is intentionally omitted here: the Scene was already created
            // with the correct basemap style in ArcGISMapViewModel.init. Replacing the Basemap
            // while the Scene is loading causes "weak_ptr is expired" in ArcGIS SDK.
            controller.moveCamera(position: cameraPosition)
        }
    }

    func setController(_ controller: ArcGISMapView2DController?) {
        if let controller {
            controller.moveCamera(position: cameraPosition)
        }
    }

    func onMapDesignTypeChange(value: ArcGISMapDesignType) {
        _mapDesignType = value
    }

    func setSceneViewHolder(_ holder: ArcGISMapViewHolder?) {
        sceneViewHolder = holder
    }

    func setMapView2DHolder(_ holder: ArcGISMapView2DHolder?) {
        mapView2DHolder = holder
    }

    func updateCameraPosition(_ cameraPosition: MapCameraPosition) {
        _cameraPosition = cameraPosition
    }

    private func resolveCameraPosition(_ target: MapCameraPosition) -> MapCameraPosition {
        let isUnspecified = target.zoom == 0 && target.bearing == 0 && target.tilt == 0
        return isUnspecified ? cameraPosition.copy(position: target.position) : target
    }
}
