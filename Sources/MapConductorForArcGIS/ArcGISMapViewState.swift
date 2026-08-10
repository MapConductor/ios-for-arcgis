import Combine
import Foundation
import MapConductorCore

/// ArcGIS の state。3D（SceneView）と 2D（MapView）で 1 つの state を共有する。
///
/// カメラの保持と委譲、`uiSettings`、`id` はコアの ``MapViewState`` が持つ。
/// ここに残るのは **ArcGIS 固有のもの**だけ:
///  - 2D / 3D で別のコントローラとホルダーを持ち、アタッチされている方へ寄せる
///  - `mapDesignType` の setter がアタッチ中の方のコントローラへ流す
public final class ArcGISMapViewState: MapViewState<ArcGISMapDesignType> {
    @Published private var _mapDesignType: ArcGISMapDesignType

    /// 3D（`ArcGISMapView` / SceneView）がアタッチされている間のコントローラ。
    private var sceneController: ArcGISMapViewController?

    /// 2D（`ArcGISMapView2D` / MapView）がアタッチされている間のコントローラ。
    ///
    /// 以前は 3D のコントローラしか保持しておらず、2D では `moveCameraTo` / `fitBounds` /
    /// `mapDesignType` がどこにも届かなかった（カメラ位置の値だけが更新され、地図は動かない）。
    /// 2D と 3D が同時に生きることは無いので、アタッチされている方へ委譲する。
    private var mapController: ArcGISMapView2DController?

    /// Provider-typed holder while the 3D `ArcGISMapView` (SceneView) is attached; nil in 2D mode.
    public private(set) var sceneViewHolder: ArcGISMapViewHolder?

    /// Provider-typed holder while the 2D `ArcGISMapView2D` (MapView) is attached; nil in 3D mode.
    public private(set) var mapView2DHolder: ArcGISMapView2DHolder?

    public override var mapDesignType: ArcGISMapDesignType {
        get { _mapDesignType }
        set {
            _mapDesignType = newValue
            if let sceneController {
                sceneController.setMapDesignType(newValue)
            } else {
                mapController?.setMapDesignType(newValue)
            }
        }
    }

    public init(
        id: String,
        mapDesignType: ArcGISMapDesignType = ArcGISDesign.Streets,
        cameraPosition: MapCameraPosition = .Default,
        uiSettings: MapUISettings = MapUISettings()
    ) {
        self._mapDesignType = mapDesignType
        super.init(id: id, initialCameraPosition: cameraPosition, uiSettings: uiSettings)
    }

    public convenience init(
        mapDesignType: ArcGISMapDesignType = ArcGISDesign.Streets,
        cameraPosition: MapCameraPosition = .Default,
        uiSettings: MapUISettings = MapUISettings()
    ) {
        self.init(id: UUID().uuidString, mapDesignType: mapDesignType, cameraPosition: cameraPosition, uiSettings: uiSettings)
    }

    /// アプリが `state.getMapViewHolder()?.map` でネイティブの地図を取れる形を保つための絞り込み。
    public override func getMapViewHolder() -> AnyMapViewHolder? {
        if let sceneViewHolder { return AnyMapViewHolder(sceneViewHolder) }
        if let mapView2DHolder { return AnyMapViewHolder(mapView2DHolder) }
        return nil
    }

    func setController(_ controller: ArcGISMapViewController?) {
        sceneController = controller
        // setMapDesignType is intentionally omitted here: the Scene was already created
        // with the correct basemap style in ArcGISMapViewModel.init. Replacing the Basemap
        // while the Scene is loading causes "weak_ptr is expired" in ArcGIS SDK.
        attachController(controller)
    }

    func setController(_ controller: ArcGISMapView2DController?) {
        mapController = controller
        // 3D と同じ理由で setMapDesignType は呼ばない（Map は既に正しい basemap で生成済み）。
        attachController(controller)
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
        setCameraPositionInternal(cameraPosition)
    }
}
