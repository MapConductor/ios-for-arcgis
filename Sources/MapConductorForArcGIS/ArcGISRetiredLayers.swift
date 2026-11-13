import ArcGIS
import Foundation

/// 地図から外したタイル層を、しばらく生かしておく。
///
/// ラスター・GroundImage・マーカーのタイル層（`WebTiledLayer` / `CustomTiledLayer`）は、外すと
/// 誰も持たなくなりすぐに解放される。ArcGIS はその後も、取得中だったタイル要求の失敗を
/// 層に知らせに来る（`Raster_tile_layer::initialize_` が登録したコールバック、ArcGIS の
/// ワーカースレッド上）。解放済みの層に届くとアプリが落ちる（EXC_BAD_ACCESS）。
///
/// iPad の 2D で、ラスターと GroundImage（ポリライン 2 本と一緒）を 0〜120ms おきに 400 回
/// 足し外しすると、11 回中 6 回この形で落ちた（develop でも同じ）。外した層を持つと 13 回中 0 回
/// （5 秒で 7 回、10 秒で 2D 6 回）。持つのは層のオブジェクトだけで、地図には載っていない。
///
/// いつ要求が片付くかを知らせる信号は無いので、時間で持つ。
@MainActor
enum ArcGISRetiredLayers {
    /// 外してから手放すまでの秒数。テストで短くする。
    static var holdSeconds: TimeInterval = 10

    static func retire(_ layer: Layer) {
        DispatchQueue.main.asyncAfter(deadline: .now() + holdSeconds) {
            withExtendedLifetime(layer) {}
        }
    }
}
