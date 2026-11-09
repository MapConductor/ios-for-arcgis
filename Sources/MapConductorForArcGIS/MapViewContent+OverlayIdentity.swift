import Foundation
@_spi(MapConductorDriver) import MapConductorCore

extension MapViewContent {
    /// `updateContent` を走らせるかどうかの指紋。3D・2D の地図が `.task(id:)` に渡す。
    ///
    /// 他のプロバイダは body の評価ごとに `updateContent` を呼び、コレクタが「同じ id の別インスタンス」
    /// まで見て差分を取る。ArcGIS はこの指紋が変わったときだけ呼ぶので、指紋が見落とした変化は
    /// 地図に届かない。以前は id しか混ぜておらず、同じ id の**新しい state** に差し替えても
    /// `updateContent` が走らなかった（コレクタは古い state を購読したまま）。
    ///
    /// そこで、各オーバーレイの **state のインスタンス**（`ObjectIdentifier`）を混ぜる。id は state の
    /// `let` なので、インスタンスが同じなら id も同じ。コレクタ（`OverlayCollector.sync`）や
    /// ``MarkerListIdentity`` と同じ「参照の同一性」で比べることになる。
    ///
    /// state の中身（位置・色など）は読まない。in-place の変更は各 state の購読が届けるので要らず、
    /// `@Published` の読み出しは body の評価ごとに全件ぶん積み上がる（14.4 万本で重い）。
    /// 以前の 3D の指紋はマーカーの緯度経度を読んでいたが、同じ一覧なら `syncMarkers` は
    /// ``MarkerListIdentity`` で入口で帰るので、それで描き直されることもなかった。
    ///
    /// 吹き出しは id のまま。中身の差し替えは吹き出しのコンテナが body の評価ごとに同期している。
    var overlayIdentityFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(markers.count)
        markers.forEach { hasher.combine(ObjectIdentifier($0.state)) }
        hasher.combine(polylines.count)
        polylines.forEach { hasher.combine(ObjectIdentifier($0.state)) }
        hasher.combine(polygons.count)
        polygons.forEach { hasher.combine(ObjectIdentifier($0.state)) }
        hasher.combine(circles.count)
        circles.forEach { hasher.combine(ObjectIdentifier($0.state)) }
        hasher.combine(groundImages.count)
        groundImages.forEach { hasher.combine(ObjectIdentifier($0.state)) }
        hasher.combine(rasterLayers.count)
        rasterLayers.forEach { hasher.combine(ObjectIdentifier($0.state)) }
        infoBubbles.forEach { hasher.combine($0.id) }
        return hasher.finalize()
    }
}
