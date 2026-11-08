import ArcGIS
import Foundation
@_spi(MapConductorDriver) import MapConductorCore

/// 運用レイヤ（`operationalLayers`）に載せるオーバーレイを、重なり順の帯（``OverlayBand``）の位置へ差し込む。
///
/// ArcGIS で運用レイヤに載るのはラスター・グラウンドイメージ（3D のみ）・マーカーのタイル。
/// 以前はどれも `addOperationalLayer`（一番上に積む）で、送り直したグラウンドイメージが
/// ラスターの下へ潜るなど、足した順で上下が変わっていた。
///
/// ポリゴン・サークル・ポリライン・マーカーはグラフィックスオーバーレイで、ArcGIS は
/// グラフィックスオーバーレイを常に運用レイヤより上に描く。そのため **マーカーのタイル
/// （運用レイヤ）はポリゴン等より下になる**。SDK の制約で、帯の順を守れない唯一の組み合わせ。
@MainActor
enum ArcGISOverlayStacking {
    /// 運用レイヤ → 帯のキー。レイヤは弱参照で持つので、外したものは自然に消える。
    private static let keys = NSMapTable<Layer, KeyBox>.weakToStrongObjects()

    private final class KeyBox: NSObject {
        let key: OverlayStackKey
        init(_ key: OverlayStackKey) { self.key = key }
    }

    static func add(_ layer: Layer, _ key: OverlayStackKey, to model: GeoModel) {
        register(layer, key)
        let existing = model.operationalLayers
        let index = OverlayStacking.insertionIndex(
            for: key,
            among: existing.map { keys.object(forKey: $0)?.key }
        )
        if index >= existing.count {
            model.addOperationalLayer(layer)
        } else {
            model.insertOperationalLayer(layer, at: index)
        }
    }

    /// 帯の計算に載せる（直接の位置を自分で決めて差し込むとき用）。
    static func register(_ layer: Layer, _ key: OverlayStackKey) {
        keys.setObject(KeyBox(key), forKey: layer)
    }

    /// ラスターの経路で載るレイヤの帯のキー。マーカーのタイル（`marker-tile-…`）はマーカー、
    /// ポリゴンのタイルはポリゴンの帯（``OverlayStacking/rasterKey(stateId:zIndex:)``）。
    static func rasterKey(_ state: RasterLayerState) -> OverlayStackKey {
        OverlayStacking.rasterKey(stateId: state.id, zIndex: state.zIndex)
    }
}
