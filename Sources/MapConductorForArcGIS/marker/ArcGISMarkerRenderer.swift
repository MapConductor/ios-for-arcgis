import ArcGIS
import MapConductorCore
import UIKit

@MainActor
final class ArcGISMarkerRenderer: MarkerOverlayRendererProtocol {
    typealias ActualMarker = Graphic

    private static let maxConcurrentAnimations = 30

    let markerLayer: GraphicsOverlay
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
            if params.current.fingerPrint.zIndex != params.prev.fingerPrint.zIndex {
                graphic.setAttributeValue(params.current.state.zIndex ?? 0, forKey: "zIndex")
            }
            return graphic
        }
    }

    func onRemove(data: [MarkerEntity<Graphic>]) async {
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
            await animateMarker(entity: entity, animation: .Drop, duration: 0.3)
        case .Bounce:
            await animateMarker(entity: entity, animation: .Bounce, duration: 2.0)
        }
    }

    func onPostProcess() async {
        let sorted = markerLayer.graphics.sorted {
            (($0.attributeValue(forKey: "zIndex") as? Int) ?? 0) < (($1.attributeValue(forKey: "zIndex") as? Int) ?? 0)
        }
        markerLayer.removeAllGraphics()
        sorted.forEach { markerLayer.addGraphic($0) }
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
        graphic.setAttributeValue(state.zIndex ?? 0, forKey: "zIndex")
        graphic.isVisible = state.getAnimation() == nil
        return graphic
    }

    private func makeSymbol(bitmapIcon: BitmapIcon) -> Symbol {
        let symbol = PictureMarkerSymbol(image: bitmapIcon.bitmap)
        symbol.width = Double(bitmapIcon.size.width)
        symbol.height = Double(bitmapIcon.size.height)
        symbol.offsetX = (0.5 - bitmapIcon.anchor.x) * bitmapIcon.size.width
        symbol.offsetY = (bitmapIcon.anchor.y - 0.5) * bitmapIcon.size.height
        return symbol
    }

    private static func animationStartY(in bounds: CGRect) -> CGFloat {
        -max(32.0, bounds.height * 0.2)
    }
}
