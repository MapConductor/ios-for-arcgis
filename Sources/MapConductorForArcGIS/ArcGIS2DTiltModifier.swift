import SwiftUI

/// ArcGIS の 2D `MapView` を「見た目だけ」傾けるモディファイア。
///
/// 2D `MapView` はカメラピッチを持てないため、ビューそのものを X 軸まわりに回して
/// 遠近感を作る（react-for-leaflet が CSS `rotateX` で行っているのと同じ方式）。
/// 地図側の中心・縮尺は `ArcGIS2DTiltEmulation` が受け持ち、ここは描画だけを扱う。
///
/// 回した平面には元のフレームより外側の領域が必要になる（上辺が奥へ退いて角が空く）ため、
/// `MapView` には ``planeScale`` 倍のフレームを与えてから回し、元のサイズでクリップする。
/// 拡大しても縮尺は変わらない（縮尺は解像度で決まる）ので、単に地図が広く映るだけ
/// ＝ 傾いたカメラがより広い地表を見るのと同じ効果になる。
///
/// 負の tilt は `ArcGIS2DTiltEmulation` が中心を前進させて表現するので、描画角度は
/// 常に `abs(tilt)` を使う（Leaflet の `experimentalTilt` と同じ）。
///
/// - Note: `GraphicsOverlay` の内容（マーカー・ポリゴン等）は `MapView` の内側にあるため、
///   この変換で一緒に寝る。Leaflet はネイティブマーカーを隠して直立ビルボードを別レイヤに
///   描いて回避しているが、ここでは未対応。
struct ArcGIS2DTiltModifier: ViewModifier {
    /// 論理 tilt（度）。符号は無視し、0...60 にクランプして描画角度に使う。
    let tilt: Double

    /// 回した平面が元のフレームを覆うための拡大率。
    ///
    /// 正射影なら回した後の高さは `planeScale * cos(tilt)` なので、最大 60° でちょうど 1.0 に
    /// なる 2.0 が最小値。react-for-leaflet / react-for-openlayers の 200% と同じ。
    private let planeScale: CGFloat = 2.0

    /// 遠近は掛けない（正射影）。
    ///
    /// react-for-leaflet / react-for-openlayers の CSS も `perspective` を置いておらず、
    /// ``planeScale`` = 1 / cos(60°) がちょうど効く前提になっている。遠近を入れると遠方が
    /// 縮んで平面が上辺を覆えなくなる。
    private let perspective: CGFloat = 0

    private var angle: Double { min(max(abs(tilt), 0.0), 60.0) }

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .frame(
                    width: geometry.size.width * planeScale,
                    height: geometry.size.height * planeScale
                )
                .rotation3DEffect(
                    .degrees(angle),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .center,
                    perspective: perspective
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
    }
}

extension View {
    /// 2D `MapView` に tilt の見た目を与える。詳細は ``ArcGIS2DTiltModifier``。
    func arcGIS2DTilt(_ tilt: Double) -> some View {
        modifier(ArcGIS2DTiltModifier(tilt: tilt))
    }
}
