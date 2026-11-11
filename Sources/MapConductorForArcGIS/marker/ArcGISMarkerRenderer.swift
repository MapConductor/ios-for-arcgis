import ArcGIS
@_spi(MapConductorDriver) import MapConductorCore
import UIKit

@MainActor
final class ArcGISMarkerRenderer: MarkerOverlayRendererProtocol, MarkerDrawOrderFrameReceiver {
    typealias ActualMarker = Graphic

    private static let maxConcurrentAnimations = 30

    let markerLayer: GraphicsOverlay
    private let stackOrder = ArcGISGraphicsZIndex()

    /// 重なり順を出すときの地図の向き（``MarkerDrawOrder``）。回すとコントローラが差し替える。
    private var drawOrderFrame: MarkerDrawOrder.Frame = .northUp

    /// 同じ zIndex の中の順位。回したあとの画面で下・左ほど上（``MarkerDrawOrder``）。
    private func tie(_ state: MarkerState) -> Double {
        MarkerDrawOrder.key(zIndex: nil, position: state.position, frame: drawOrderFrame)
    }

    /// 回したら、同じ zIndex の中の順位を付け直す。3D は GraphicsOverlay の並びでも決まるので
    /// 並びもそろえる（``onPostProcess()``）。
    func onDrawOrderFrameChanged(_ frame: MarkerDrawOrder.Frame, entities: [MarkerEntity<Graphic>]) async {
        drawOrderFrame = frame
        stackOrder.retie(entities.compactMap { entity in
            entity.marker.map { (graphic: $0, tie: tie(entity.state)) }
        })
        syncOverlayOrderIfNeeded()
    }
    private weak var container: (any ArcGISMapContext)?
    private var markerAnimationRunners: [String: MarkerAnimationRunner] = [:]
    private var deferredAnimateAttemptsById: [String: Int] = [:]

    var animateStartListener: OnMarkerEventHandler?
    var animateEndListener: OnMarkerEventHandler?

    /// When set, drop/bounce animations run on the screen-space overlay layer
    /// (projection-independent: correct on tilted/rotated/globe views) and the
    /// native graphic is hidden for the duration.
    var animationOverlay: MarkerAnimationOverlayCoordinator?

    init(markerLayer: GraphicsOverlay, container: any ArcGISMapContext) {
        self.markerLayer = markerLayer
        self.container = container
    }

    func onAdd(data: [MarkerOverlayAddParams]) async -> [Graphic?] {
        data.map { params in
            let graphic = makeGraphic(state: params.state, bitmapIcon: params.bitmapIcon)
            stackOrder.place(graphic, params.state.zIndex, tie: tie(params.state))
            markerLayer.addGraphic(graphic)
            return graphic
        }
    }

    func onChange(data: [MarkerOverlayChangeParams<Graphic>]) async -> [Graphic?] {
        data.map { params in
            let graphic = params.prev.marker ?? makeGraphic(state: params.current.state, bitmapIcon: params.bitmapIcon)
            graphic.geometry = params.current.state.position.toArcGISPoint(spatialReference: .wgs84)
            graphic.isVisible = params.current.visible
                && !(params.current.state.getAnimation() != nil && markerAnimationRunners[params.current.state.id] == nil)
            if params.current.fingerPrint.icon != params.prev.fingerPrint.icon {
                graphic.symbol = makeSymbol(bitmapIcon: params.bitmapIcon)
            }
            // 地図に載っている Graphic（prev.marker）だけを順位表に置く。同じ zIndex の中の順位は
            // 位置で決まるので、位置が変わっても置き直す（変わっていなければ place が何もしない）。
            if params.prev.marker != nil {
                stackOrder.place(graphic, params.current.state.zIndex, tie: tie(params.current.state))
            }
            return graphic
        }
    }

    func onRemove(data: [MarkerEntity<Graphic>]) async {
        stackOrder.forget(data.compactMap(\.marker))
        for entity in data {
            markerAnimationRunners[entity.state.id]?.stop()
            markerAnimationRunners.removeValue(forKey: entity.state.id)
            deferredAnimateAttemptsById.removeValue(forKey: entity.state.id)
            if let graphic = entity.marker {
                markerLayer.removeGraphic(graphic)
            }
        }
    }

    func onAnimate(entity: MarkerEntity<Graphic>) async {
        guard markerAnimationRunners[entity.state.id] == nil else { return }
        guard let animation = entity.state.getAnimation() else { return }

        switch animation {
        case .Drop:
            await animateMarker(entity: entity, animation: .Drop, duration: Settings.Default.markerDropAnimateInterval)
        case .Bounce:
            await animateMarker(entity: entity, animation: .Bounce, duration: Settings.Default.markerBounceAnimateInterval)
        }
    }

    /// 重なり順は各 Graphic の zIndex が持つ（``ArcGISGraphicsZIndex``）。2D はそれで足りる。
    /// 3D（SceneView）は Graphic の `zIndex` で並べない。同じ地点のマーカーは GraphicsOverlay の
    /// 並び（後ろほど上）で描かれ、`zIndex=1` を先に足すと後から足した `zIndex` なしの下になった
    /// （iPad。`surfacePlacement` を `.drapedBillboarded` にしても同じ）。そこで並びも順位の順に
    /// 保つ。並んでいれば何もしない。崩れていたときだけ入れ直す。
    func onPostProcess() async {
        syncOverlayOrderIfNeeded()
    }

    private func syncOverlayOrderIfNeeded() {
        let graphics = markerLayer.graphics
        var previous = Int.min
        var ordered = true
        for graphic in graphics {
            guard let rank = stackOrder.rank(of: graphic) else { continue }
            if rank < previous { ordered = false; break }
            previous = rank
        }
        if ordered { return }
        // 順位表に無い Graphic（別のレンダラが同じ層へ足したもの）は前に、元の並びのまま置く。
        let sorted = graphics.enumerated()
            .sorted { (stackOrder.rank(of: $0.element) ?? Int.min, $0.offset) < (stackOrder.rank(of: $1.element) ?? Int.min, $1.offset) }
            .map(\.element)
        markerLayer.removeAllGraphics()
        markerLayer.addGraphics(sorted)
    }

    func unbind() {
        markerAnimationRunners.values.forEach { $0.stop() }
        markerAnimationRunners.removeAll()
        deferredAnimateAttemptsById.removeAll()
        container = nil
    }

    private func animateMarker(
        entity: MarkerEntity<Graphic>,
        animation: MarkerAnimation,
        duration: CFTimeInterval
    ) async {
        guard let graphic = entity.marker else { return }

        // Preferred path: animate the marker image on the screen-space overlay.
        // Projection-independent (3D SceneView / rotated headings stay correct)
        // and needs none of the deferral/projection sanity checks below.
        if let overlay = animationOverlay {
            graphic.geometry = GeoPoint(
                latitude: entity.state.position.latitude,
                longitude: entity.state.position.longitude,
                altitude: entity.state.position.altitude ?? 0
            ).toArcGISPoint(spatialReference: SpatialReference.wgs84)
            graphic.isVisible = false
            animateStartListener?(entity.state)
            let icon = (entity.state.icon ?? DefaultMarkerIcon()).toBitmapIcon()
            let visibleAfter = entity.visible
            overlay.start(MarkerAnimationOverlayEntry(
                id: entity.state.id,
                state: entity.state,
                icon: icon,
                animation: animation,
                duration: duration,
                onFinished: { [weak self] in
                    graphic.isVisible = visibleAfter
                    entity.state.animate(nil)
                    self?.animateEndListener?(entity.state)
                }
            ))
            return
        }

        guard let container else {
            await deferAnimate(entity: entity)
            return
        }
        guard let viewportSize = container.viewportSize, viewportSize.width > 0, viewportSize.height > 0 else {
            await deferAnimate(entity: entity)
            return
        }
        if markerAnimationRunners.count >= Self.maxConcurrentAnimations {
            applyImmediatePosition(for: entity, to: graphic)
            return
        }

        let targetGeoPoint = GeoPoint(
            latitude: entity.state.position.latitude,
            longitude: entity.state.position.longitude,
            altitude: entity.state.position.altitude ?? 0
        )
        let targetPoint = targetGeoPoint.toArcGISPoint(spatialReference: SpatialReference.wgs84)
        guard let targetScreenPoint = container.screenPoint(fromLocation: targetPoint),
              targetScreenPoint.x.isFinite,
              targetScreenPoint.y.isFinite else {
            await deferAnimate(entity: entity)
            return
        }

        let bounds = CGRect(origin: .zero, size: viewportSize)
        if !bounds.contains(targetScreenPoint) {
            applyImmediatePosition(for: entity, to: graphic)
            return
        }

        let startScreenPoint = CGPoint(x: targetScreenPoint.x, y: Self.animationStartY(in: bounds))
        guard let startGeoPoint = await container.location(fromScreenPoint: startScreenPoint) else {
            await deferAnimate(entity: entity)
            return
        }

        let pathPoints = animation == .Bounce
            ? await bouncePath(for: container, targetScreenPoint: targetScreenPoint, target: targetGeoPoint)
            : MarkerAnimationRunner.makeLinearPath(start: startGeoPoint, target: targetGeoPoint)

        graphic.geometry = startGeoPoint.toArcGISPoint(spatialReference: SpatialReference.wgs84)
        graphic.isVisible = entity.visible
        animateStartListener?(entity.state)

        let runner = MarkerAnimationRunner(
            duration: duration,
            pathPoints: pathPoints,
            onUpdate: { [weak self] point in
                guard let self else { return }
                self.updateAnimatedGraphic(graphic, point: point)
            },
            onCompletion: { [weak self] in
                graphic.geometry = targetGeoPoint.toArcGISPoint(spatialReference: SpatialReference.wgs84)
                graphic.isVisible = entity.visible
                entity.state.animate(nil)
                self?.markerAnimationRunners.removeValue(forKey: entity.state.id)
                self?.deferredAnimateAttemptsById.removeValue(forKey: entity.state.id)
                self?.animateEndListener?(entity.state)
            }
        )
        markerAnimationRunners[entity.state.id] = runner
        runner.start()
    }

    private func updateAnimatedGraphic(_ graphic: Graphic, point: GeoPoint) {
        graphic.geometry = point.toArcGISPoint(spatialReference: SpatialReference.wgs84)
        markerLayer.removeGraphic(graphic)
        markerLayer.addGraphic(graphic)
    }

    private func deferAnimate(entity: MarkerEntity<Graphic>) async {
        let id = entity.state.id
        let attempts = (deferredAnimateAttemptsById[id] ?? 0) + 1
        deferredAnimateAttemptsById[id] = attempts
        guard attempts <= 20 else {
            deferredAnimateAttemptsById.removeValue(forKey: id)
            if let graphic = entity.marker {
                applyImmediatePosition(for: entity, to: graphic)
            } else {
                entity.state.animate(nil)
                animateEndListener?(entity.state)
            }
            return
        }
        try? await Task.sleep(nanoseconds: 16_000_000)
        await onAnimate(entity: entity)
    }

    private func applyImmediatePosition(for entity: MarkerEntity<Graphic>, to graphic: Graphic) {
        graphic.geometry = entity.state.position.toArcGISPoint(spatialReference: .wgs84)
        graphic.isVisible = entity.visible
        entity.state.animate(nil)
        animateEndListener?(entity.state)
    }

    private func bouncePath(
        for container: any ArcGISMapContext,
        targetScreenPoint: CGPoint,
        target: GeoPoint
    ) async -> [GeoPoint] {
        var points: [GeoPoint] = []
        let bounces = 3
        for index in 0...bounces * 10 {
            let progress = Double(index) / Double(bounces * 10)
            let bounce = abs(sin(progress * Double.pi * Double(bounces))) * (1.0 - progress)
            let y = targetScreenPoint.y - bounce * 80.0
            if let point = await container.location(fromScreenPoint: CGPoint(x: targetScreenPoint.x, y: y)) {
                points.append(point)
            }
        }
        if points.isEmpty || points.last != target {
            points.append(target)
        }
        return points
    }

    private func makeGraphic(state: MarkerState, bitmapIcon: BitmapIcon) -> Graphic {
        let graphic = Graphic(
            geometry: state.position.toArcGISPoint(spatialReference: .wgs84),
            symbol: makeSymbol(bitmapIcon: bitmapIcon)
        )
        graphic.setAttributeValue(state.id, forKey: "id")
        // 縦補正の掛け直しに使う素の寸法（tilt が変わるたびにここから再計算する）。
        graphic.setAttributeValue(Double(bitmapIcon.size.height), forKey: Self.baseHeightKey)
        graphic.setAttributeValue(
            (bitmapIcon.anchor.y - 0.5) * Double(bitmapIcon.size.height),
            forKey: Self.baseOffsetYKey
        )
        graphic.isVisible = state.getAnimation() == nil
        return graphic
    }

    private func makeSymbol(bitmapIcon: BitmapIcon) -> Symbol {
        let symbol = PictureMarkerSymbol(image: bitmapIcon.bitmap)
        symbol.width = Double(bitmapIcon.size.width)
        symbol.height = Double(bitmapIcon.size.height)
        symbol.offsetX = (0.5 - bitmapIcon.anchor.x) * bitmapIcon.size.width
        symbol.offsetY = (bitmapIcon.anchor.y - 0.5) * bitmapIcon.size.height
        applyVerticalStretch(to: symbol, baseHeight: symbol.height, baseOffsetY: symbol.offsetY)
        return symbol
    }

    /// 2D の tilt 表現でビューが縦に潰れるぶんを、マーカーだけ先に引き伸ばして打ち消す。
    /// アンカーが地面の位置からずれないよう `offsetY` も同じ倍率で補正する。
    private func applyVerticalStretch(to symbol: PictureMarkerSymbol, baseHeight: Double, baseOffsetY: Double) {
        let stretch = container?.markerVerticalStretch ?? 1.0
        symbol.height = baseHeight * stretch
        symbol.offsetY = baseOffsetY * stretch
    }

    /// tilt が変わったときに、既存マーカーの縦補正を掛け直す。
    ///
    /// 元の高さ・オフセットは生成時に属性へ控えてあるので、そこから毎回作り直す
    /// （倍率を累積させない）。
    func refreshVerticalStretch() {
        for graphic in markerLayer.graphics {
            guard let symbol = graphic.symbol as? PictureMarkerSymbol,
                  let baseHeight = graphic.attributes[Self.baseHeightKey] as? Double,
                  let baseOffsetY = graphic.attributes[Self.baseOffsetYKey] as? Double
            else { continue }
            applyVerticalStretch(to: symbol, baseHeight: baseHeight, baseOffsetY: baseOffsetY)
        }
    }

    static let baseHeightKey = "mcBaseHeight"
    static let baseOffsetYKey = "mcBaseOffsetY"

    private static func animationStartY(in bounds: CGRect) -> CGFloat {
        -max(32.0, bounds.height * 0.2)
    }
}
