import ArcGIS
import Foundation
import MapConductorCore

@MainActor
final class ArcGISRasterLayerOverlayRenderer: AbstractRasterLayerOverlayRenderer<Layer> {
    private let addLayer: (Layer) -> Void
    private let removeLayerFn: (Layer) -> Void

    convenience init(scene: ArcGIS.Scene) {
        self.init(
            addLayer: { [weak scene] layer in scene?.addOperationalLayer(layer) },
            removeLayer: { [weak scene] layer in scene?.removeOperationalLayer(layer) }
        )
    }

    convenience init(map: ArcGIS.Map) {
        self.init(
            addLayer: { [weak map] layer in map?.addOperationalLayer(layer) },
            removeLayer: { [weak map] layer in map?.removeOperationalLayer(layer) }
        )
    }

    init(addLayer: @escaping (Layer) -> Void, removeLayer: @escaping (Layer) -> Void) {
        self.addLayer = addLayer
        self.removeLayerFn = removeLayer
        super.init()
    }

    override func createLayer(state: RasterLayerState) async -> Layer? {
        RasterHeaderRuleSet.warnUnsupported(provider: "ArcGIS", state: state)
        guard let layer = makeLayer(from: state) else { return nil }
        apply(state: state, to: layer)
        if state.debug {
            NSLog("[MapConductor] RasterLayer debug mode: id=%@", state.id)
        }
        addLayer(layer)
        return layer
    }

    override func updateLayerProperties(
        layer: Layer,
        current: RasterLayerEntity<Layer>,
        prev: RasterLayerEntity<Layer>
    ) async -> Layer? {
        if current.fingerPrint.source != prev.fingerPrint.source {
            await removeLayer(entity: prev)
            guard let newLayer = makeLayer(from: current.state) else { return nil }
            apply(state: current.state, to: newLayer)
            if current.state.debug {
                NSLog("[MapConductor] RasterLayer debug mode: id=%@", current.state.id)
            }
            addLayer(newLayer)
            return newLayer
        }
        if current.fingerPrint.debug != prev.fingerPrint.debug && current.state.debug {
            NSLog("[MapConductor] RasterLayer debug mode: id=%@", current.state.id)
        }
        apply(state: current.state, to: layer)
        return layer
    }

    override func removeLayer(entity: RasterLayerEntity<Layer>) async {
        guard let layer = entity.layer else { return }
        removeLayerFn(layer)
    }

    private func apply(state: RasterLayerState, to layer: Layer) {
        layer.opacity = Float(state.opacity)
        layer.isVisible = state.visible
    }

    private func makeLayer(from state: RasterLayerState) -> Layer? {
        switch state.source {
        case let .arcGisService(serviceUrl):
            guard let url = URL(string: serviceUrl) else { return nil }
            return ArcGISTiledLayer(url: url)
        case let .urlTemplate(template, tileSize, _, _, _, scheme):
            if scheme == .TMS {
                NSLog("[MapConductor] ArcGIS RasterLayer: TMS scheme is not supported. id=%@", state.id)
                return nil
            }
            let converted = template
                .replacingOccurrences(of: "{z}", with: "{level}")
                .replacingOccurrences(of: "{x}", with: "{col}")
                .replacingOccurrences(of: "{y}", with: "{row}")
            return WebTiledLayer(
                urlTemplate: converted,
                subDomains: [],
                tileInfo: Self.webMercatorTileInfo(tileSize: tileSize)
            )
        case .tileJson:
            NSLog("[MapConductor] ArcGIS RasterLayer: tileJson sources are not supported. id=%@", state.id)
            return nil
        }
    }

    /// XYZ タイルの敷き方を、宣言された `tileSize` どおりに組む。
    ///
    /// ## 既定のまま作ると半分の大きさで描かれる
    ///
    /// `WebTiledLayer(urlTemplate:subDomains:)` は `defaultTileInfo`（**256 ピクセル**の
    /// Web メルカトル）を使う。MapConductor のラスターは既定 512 なので、512 の画像が
    /// 256 ポイントの枠へ押し込まれ、**中身がちょうど半分の大きさで描かれる**。
    ///
    /// 実測（地図ズーム 13、GeoJSON レイヤ、iPhone シミュレータ）: MapLibre は z=12 の
    /// タイルを要求して線が 18px、ArcGIS 2D は z=13 を要求して 9px だった。
    /// 「ArcGIS だけポリラインが異常に細い」の正体がこれ。ヒートマップとタイル方式
    /// マーカーも同じだけ縮んでいた（どちらも半分なので単体では気づきにくい）。
    ///
    /// ## 解像度は「タイルの地理的な広さ」を固定して決めること
    ///
    /// URL は XYZ なので、level `z` のタイルが覆う地表の広さは `tileSize` に依らず
    /// 赤道一周 ÷ 2^z で決まっている。したがって 1 ピクセルあたりの解像度は
    /// `tileSize` に**反比例**させる。ここを 256 のままにすると、レイヤは正しい大きさで
    /// 敷かれるのに**別の level のタイルを取りに行く**（地図がずれた位置に描かれる）。
    ///
    /// ## android とここだけ形が違う
    ///
    /// android-for-arcgis の `resolveLodReferenceTileSize` は、tileWidth は 512 のまま
    /// **解像度だけ 256 基準**で組んでいる。あちらの SDK は tileWidth に関係なく
    /// (col,row) を 256 グリッドで計算してしまい、素直に組むと (z,x,y) がずれるため。
    /// iOS の SDK にはその癖が無く、素直に組んで実測でも位置は動かなかった
    /// （赤紫の路線の画面 y 座標が修正の前後で 660/1769 のまま）。
    /// **android の書き方を持ち込まないこと。** 持ち込むと今度は iOS がずれる。
    private static func webMercatorTileInfo(tileSize: Int) -> TileInfo {
        let size = max(1, tileSize)
        let levels = (0...maxTileLevel).map { level -> LevelOfDetail in
            let resolution = equatorMeters / (Double(size) * pow(2.0, Double(level)))
            return LevelOfDetail(
                level: level,
                resolution: resolution,
                // 縮尺の分母。ArcGIS は「画面の縮尺に一番近い level」を選ぶので、
                // 解像度と同じ比率で縮んでいないと 1 段ずれる。
                scale: resolution * Double(tileDpi) / metersPerInch
            )
        }
        return TileInfo(
            dpi: tileDpi,
            format: .png,
            levelsOfDetail: levels,
            origin: Point(x: -equatorMeters / 2, y: equatorMeters / 2, spatialReference: .webMercator),
            spatialReference: .webMercator,
            tileHeight: size,
            tileWidth: size
        )
    }

    /// Web メルカトルの赤道一周（メートル）。
    private static let equatorMeters = 40_075_016.685_578_5

    /// ArcGIS の縮尺計算の基準 dpi。`defaultTileInfo` と同じ 96 を使う。
    private static let tileDpi = 96

    private static let metersPerInch = 0.0254

    /// XYZ タイルの上限。web メルカトルの一般的な範囲に合わせる。
    private static let maxTileLevel = 23
}
