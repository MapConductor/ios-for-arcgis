import ArcGIS
import Foundation
import MapConductorCore
import UIKit

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

    /**
     Draws one tile in the process, off Swift's cooperative pool.

     `renderLocalTile` is synchronous and blocks: it waits for one of the
     server's render slots, then rasterises. Called straight from the
     `CustomTiledLayer` closure it blocks a cooperative thread, and there are
     only as many of those as the device has cores. ArcGIS's 3D view asks for
     around 120 tiles at once, so the pool filled with threads waiting on a
     six-wide gate, the work that would have released the gate had nowhere to
     run, and the map stopped: measured on an iPad, four tiles in thirty
     seconds and a blank screen.

     A queue of its own gives the blocking work real threads. The continuation
     hands the bytes back without holding a cooperative thread while it waits.

     Cancellation is read through a box rather than `Task.isCancelled` inside
     the closure: by then the work is on this queue, where there is no current
     task and the answer would always be "no". `withTaskCancellationHandler`
     ticks the box from whichever context ArcGIS cancels on.
     */
    private static let directTileQueue = DispatchQueue(
        label: "MapConductorForArcGIS.directTile",
        qos: .utility,
        attributes: .concurrent
    )

    /**
     The level the camera is looking at, as ArcGIS numbers them, so a request
     for some other level can wait its turn instead of taking a render slot.

     A zoom out of a few pinches puts several hundred requests in flight, and
     most are for levels the camera has already left: on an iPad, 359 of 581
     tiles drawn for one such gesture were never seen. ArcGIS does cancel them
     — but only the ones that have not started, and with six render slots and
     a queue that fills faster than it drains, a stale request usually starts
     before the cancellation arrives and is then drawn to the end.

     So a request far from the current level is held back, off the queue, for
     a moment. If ArcGIS cancels it meanwhile it costs nothing; if the camera
     catches up with it, it goes ahead; and if neither happens within the
     allowance it goes ahead anyway. It is never answered with nothing: an
     earlier attempt returned nil for such requests, and ArcGIS took that as
     "there is no tile here" and left holes until the layer was rebuilt.

     `MapCameraPosition.zoom` is MapConductor's one yardstick on every provider
     (Google's zoom, 256 px tiles). The 3D view picks the level whose tile
     covers 256 *device* pixels of ground -- by ground extent, not by index:
     a ladder shifted two levels made it pick 15 where it had picked 13, and
     shows every tile across those 256 pixels whatever `tileWidth` says, so no
     ladder makes it show a bigger tile. With the honest ladder that level is
     the zoom plus log2(scale). Per renderer, because two ArcGIS maps on one
     screen look at different zooms.
     */
    final class LevelBox: @unchecked Sendable {
        private let lock = NSLock()
        private var level: Int?
        private var changedAt: Date?

        func set(unifiedZoom: Double, displayScale: Double) {
            let wanted = Int((unifiedZoom + log2(max(1.0, displayScale))).rounded())
            lock.lock()
            if wanted != level {
                level = wanted
                changedAt = Date()
            }
            lock.unlock()
        }

        /// Whether a request may go straight to the queue.
        ///
        /// Off-level requests are held back only while the camera is moving,
        /// or has just stopped. The level alone cannot tell the two cases
        /// apart: on first load ArcGIS wants every ancestor, in order, before
        /// it issues the level on screen, so holding ancestors held everything
        /// (19 tiles of the level on screen in five seconds against 58). A zoom
        /// out leaves the same shape of request behind — levels away from the
        /// camera — but there the camera has just changed, and those requests
        /// are the ones a cancellation is about to reach. So the moving camera
        /// is the signal, not the level.
        func isReady(level requested: Int) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard let level, let changedAt else { return true }
            if Date().timeIntervalSince(changedAt) > Self.settled { return true }
            return abs(requested - level) <= 1
        }

        /// How long after the camera stops that off-level requests are still
        /// treated as left over from the movement.
        static let settled: TimeInterval = 1.0
    }

    private let currentLevel = LevelBox()

    func cameraMoved(unifiedZoom: Double) {
        currentLevel.set(unifiedZoom: unifiedZoom, displayScale: Double(UIScreen.main.scale))
    }

    /// How long a stale request may be held before it is drawn regardless.
    /// Long enough for a cancellation to arrive, short enough that a level the
    /// camera genuinely wants is not kept waiting noticeably.
    private static let staleRequestAllowance: TimeInterval = 1.5

    private final class CancelBox: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        func cancel() {
            lock.lock(); cancelled = true; lock.unlock()
        }

        var isCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return cancelled
        }
    }

    private static func renderOffTheCooperativePool(
        server: LocalTileServer,
        url: URL
    ) async -> Data? {
        let box = CancelBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                directTileQueue.async {
                    continuation.resume(
                        returning: server.renderLocalTile(url: url) { box.isCancelled }
                    )
                }
            }
        } onCancel: {
            box.cancel()
        }
    }

    func isDirectLocalLayer(state: RasterLayerState) -> Bool {
        guard case let .urlTemplate(template, _, _, _, _, _) = state.source else { return false }
        let server = TileServerRegistry.get()
        return template.hasPrefix(server.baseUrl + "/")
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

            // MapConductor-generated tiles already live in this process. The
            // ArcGIS callback carries real task cancellation, whereas a local
            // HTTP server cannot distinguish "request body is finished" from
            // "the client abandoned the response" by looking at a TCP FIN.
            // Calling the registered provider directly both removes the
            // loopback hop and lets obsolete fly-through/pan tiles stop taking
            // render slots immediately.
            let server = TileServerRegistry.get()
            let levels = currentLevel
            if template.hasPrefix(server.baseUrl + "/") {
                return CustomTiledLayer(
                    tileInfo: Self.webMercatorTileInfo(tileSize: tileSize),
                    fullExtent: ImageTiledLayer.defaultFullExtent
                ) { key in
                    guard !Task.isCancelled else { return nil }
                    // A request for a level the camera is not looking at
                    // waits here, off the queue, for a cancellation that
                    // usually comes. See `LevelBox`.
                    let deadline = Date().addingTimeInterval(Self.staleRequestAllowance)
                    while !levels.isReady(level: key.level), Date() < deadline {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        if Task.isCancelled { return nil }
                    }
                    let urlText = template
                        .replacingOccurrences(of: "{z}", with: String(key.level))
                        .replacingOccurrences(of: "{x}", with: String(key.column))
                        .replacingOccurrences(of: "{y}", with: String(key.row))
                    guard let url = URL(string: urlText) else { return nil }
                    return await Self.renderOffTheCooperativePool(server: server, url: url)
                }
            }
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
    /// ## android も同じ形（2026-09 に揃えた）
    ///
    /// android-for-arcgis には「3D SceneView は 256 基準でないと何も要求しない」
    /// という読み替え（`resolveLodReferenceTileSize`）があり、512 のときだけ
    /// 解像度を 256 基準で組んでいた。tileWidth は 512 のままなので、レベル L の
    /// タイルが L-1 の広さを覆う**番号だけ 1 段深い格子**になり、実機で
    /// 「z=13, x=3637」（東京の z=13 は x=7276）という噛み合わない組を引いて
    /// 大西洋のタイルを描いていた。ArcGIS 300 では読み替え無しで 2D/3D とも
    /// 正しく引くので削除済み。**どちらのプラットフォームでも tileSize 基準。**
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
