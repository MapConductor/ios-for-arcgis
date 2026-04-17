import Combine
import Foundation
import MapConductorCore

public final class ArcGISMapViewState: MapViewState<ArcGISMapDesignType> {
    private let stateId: String

    @Published private var _cameraPosition: MapCameraPosition
    @Published private var _mapDesignType: ArcGISMapDesignType

    private var controller: ArcGISMapViewController?
    private var mapViewHolder: AnyMapViewHolder?

    public override var id: String { stateId }
    public override var cameraPosition: MapCameraPosition { _cameraPosition }

    public override var mapDesignType: ArcGISMapDesignType {
        get { _mapDesignType }
        set {
            _mapDesignType = newValue
            controller?.setMapDesignType(newValue)
        }
    }

    public init(
        id: String,
        mapDesignType: ArcGISMapDesignType = ArcGISDesign.Streets,
        cameraPosition: MapCameraPosition = .Default
    ) {
        self.stateId = id
        self._mapDesignType = mapDesignType
        self._cameraPosition = cameraPosition
        super.init()
    }

    public convenience init(
        mapDesignType: ArcGISMapDesignType = ArcGISDesign.Streets,
        cameraPosition: MapCameraPosition = .Default
    ) {
        self.init(id: UUID().uuidString, mapDesignType: mapDesignType, cameraPosition: cameraPosition)
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

    public override func moveCameraTo(position: GeoPoint, durationMillis: Long? = 0) {
        moveCameraTo(cameraPosition: cameraPosition.copy(position: position), durationMillis: durationMillis)
    }

    public override func getMapViewHolder() -> AnyMapViewHolder? {
        mapViewHolder
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

    func setMapViewHolder(_ holder: AnyMapViewHolder?) {
        mapViewHolder = holder
    }

    func updateCameraPosition(_ cameraPosition: MapCameraPosition) {
        _cameraPosition = cameraPosition
    }

    private func resolveCameraPosition(_ target: MapCameraPosition) -> MapCameraPosition {
        let isUnspecified = target.zoom == 0 && target.bearing == 0 && target.tilt == 0
        return isUnspecified ? cameraPosition.copy(position: target.position) : target
    }
}
