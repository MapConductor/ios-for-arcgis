import ArcGIS
import MapConductorCore
import UIKit

@MainActor
final class ArcGISMarkerRenderer: MarkerOverlayRendererProtocol {
    typealias ActualMarker = Graphic

    let markerLayer: GraphicsOverlay
    var animateStartListener: OnMarkerEventHandler?
    var animateEndListener: OnMarkerEventHandler?

    init(markerLayer: GraphicsOverlay) {
        self.markerLayer = markerLayer
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
            if params.current.fingerPrint.icon != params.prev.fingerPrint.icon {
                graphic.symbol = makeSymbol(bitmapIcon: params.bitmapIcon)
            }
            return graphic
        }
    }

    func onRemove(data: [MarkerEntity<Graphic>]) async {
        data.compactMap(\.marker).forEach { markerLayer.removeGraphic($0) }
    }

    func onAnimate(entity: MarkerEntity<Graphic>) async {
        animateStartListener?(entity.state)
        entity.state.animate(nil)
        animateEndListener?(entity.state)
    }

    func onPostProcess() async {}

    private func makeGraphic(state: MarkerState, bitmapIcon: BitmapIcon) -> Graphic {
        let graphic = Graphic(
            geometry: state.position.toArcGISPoint(spatialReference: .wgs84),
            symbol: makeSymbol(bitmapIcon: bitmapIcon)
        )
        graphic.setAttributeValue(state.id, forKey: "id")
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
}
