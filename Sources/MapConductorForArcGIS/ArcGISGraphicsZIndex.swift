import ArcGIS

/// 帯の中の重なり順（zIndex）。ポリゴン・サークル・ポリライン・マーカーの Graphic に使う。
///
/// 帯（ポリゴン < サークル < ポリライン < マーカー）は GraphicsOverlay 自体の並びで決まる
/// （``ArcGISOverlayStacking``）。帯の**中**は、各 Graphic の `zIndex` で決める。3D（SceneView）・
/// 2D（MapView）とも、同じ GraphicsOverlay の中はこの値の順に描かれ、同じ値なら足した順になる。
///
/// 以前は zIndex を属性（`"zIndex"`）に書き、`onPostProcess` で `removeAllGraphics` → 再追加で
/// 並べ替えていた（サークルは並べ替えもしていなかった）。iPad では、zIndex=1 を先に、zIndex=0 を
/// 後に足すと、サークルとポリラインは 3D・2D とも zIndex=1 が下に残った。`zIndex` だけで
/// 正しく描かれるので、並べ替えはやめた（全マーカーの外し直しも要らなくなる）。
enum ArcGISGraphicsZIndex {
    /// `graphic` に `zIndex` を載せる。`nil`（サークル・マーカーの既定）は 0。
    static func apply(_ graphic: Graphic, _ zIndex: Int?) {
        let value = zIndex ?? 0
        if graphic.zIndex != value { graphic.zIndex = value }
    }
}
