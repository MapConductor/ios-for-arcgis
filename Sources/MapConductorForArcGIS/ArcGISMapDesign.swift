import ArcGIS
import MapConductorCore

public protocol ArcGISMapDesignTypeProtocol: MapDesignTypeProtocol where Identifier == String {
    var elevationSources: [String] { get }
}

public typealias ArcGISMapDesignType = any ArcGISMapDesignTypeProtocol

public struct ArcGISDesign: ArcGISMapDesignTypeProtocol, Hashable {
    public let id: String
    public let elevationSources: [String]

    public init(id: String, elevationSources: [String] = []) {
        self.id = id
        self.elevationSources = elevationSources
    }

    public func getValue() -> String {
        id
    }

    public func withElevationSources(_ sources: [String]) -> ArcGISDesign {
        ArcGISDesign(id: id, elevationSources: sources)
    }

    public static let Streets = ArcGISDesign(id: "arc_gis_streets")
    public static let Imagery = ArcGISDesign(id: "arc_gis_imagery")
    public static let ImageryStandard = ArcGISDesign(id: "arc_gis_imagery_standard")
    public static let ImageryLabels = ArcGISDesign(id: "arc_gis_imagery_labels")
    public static let LightGray = ArcGISDesign(id: "arc_gis_light_gray")
    public static let LightGrayBase = ArcGISDesign(id: "arc_gis_light_gray_base")
    public static let LightGrayLabels = ArcGISDesign(id: "arc_gis_light_gray_labels")
    public static let DarkGray = ArcGISDesign(id: "arc_gis_dark_gray")
    public static let DarkGrayBase = ArcGISDesign(id: "arc_gis_dark_gray_base")
    public static let DarkGrayLabels = ArcGISDesign(id: "arc_gis_dark_gray_labels")
    public static let Navigation = ArcGISDesign(id: "arc_gis_navigation")
    public static let NavigationNight = ArcGISDesign(id: "arc_gis_navigation_night")
    public static let StreetsNight = ArcGISDesign(id: "arc_gis_streets_night")
    public static let StreetsRelief = ArcGISDesign(id: "arc_gis_streets_relief")
    public static let Topographic = ArcGISDesign(id: "arc_gis_topographic")
    public static let Oceans = ArcGISDesign(id: "arc_gis_oceans")
    public static let OceansBase = ArcGISDesign(id: "arc_gis_oceans_base")
    public static let OceansLabels = ArcGISDesign(id: "arc_gis_oceans_labels")
    public static let Terrain = ArcGISDesign(id: "arc_gis_terrain")
    public static let TerrainBase = ArcGISDesign(id: "arc_gis_terrain_base")
    public static let TerrainDetail = ArcGISDesign(id: "arc_gis_terrain_detail")
    public static let Community = ArcGISDesign(id: "arc_gis_community")
    public static let ChartedTerritory = ArcGISDesign(id: "arc_gis_charted_territory")
    public static let ColoredPencil = ArcGISDesign(id: "arc_gis_colored_pencil")
    public static let Nova = ArcGISDesign(id: "arc_gis_nova")
    public static let ModernAntique = ArcGISDesign(id: "arc_gis_modern_antique")
    public static let Midcentury = ArcGISDesign(id: "arc_gis_midcentury")
    public static let Newspaper = ArcGISDesign(id: "arc_gis_newspaper")
    public static let HillshadeLight = ArcGISDesign(id: "arc_gis_hillshade_light")
    public static let HillshadeDark = ArcGISDesign(id: "arc_gis_hillshade_dark")
    public static let StreetsReliefBase = ArcGISDesign(id: "arc_gis_streets_relief_base")
    public static let TopographicBase = ArcGISDesign(id: "arc_gis_topographic_base")
    public static let ChartedTerritoryBase = ArcGISDesign(id: "arc_gis_charted_territory_base")
    public static let ModernAntiqueBase = ArcGISDesign(id: "arc_gis_modern_antique_base")
    public static let HumanGeography = ArcGISDesign(id: "arc_gis_human_geography")
    public static let HumanGeographyBase = ArcGISDesign(id: "arc_gis_human_geography_base")
    public static let HumanGeographyDetail = ArcGISDesign(id: "arc_gis_human_geography_detail")
    public static let HumanGeographyLabels = ArcGISDesign(id: "arc_gis_human_geography_labels")
    public static let HumanGeographyDark = ArcGISDesign(id: "arc_gis_human_geography_dark")
    public static let HumanGeographyDarkBase = ArcGISDesign(id: "arc_gis_human_geography_dark_base")
    public static let HumanGeographyDarkDetail = ArcGISDesign(id: "arc_gis_human_geography_dark_detail")
    public static let HumanGeographyDarkLabels = ArcGISDesign(id: "arc_gis_human_geography_dark_labels")
    public static let Outdoor = ArcGISDesign(id: "arc_gis_outdoor")
    public static let OsmStandard = ArcGISDesign(id: "osm_standard")
    public static let OsmStandardRelief = ArcGISDesign(id: "osm_standard_relief")
    public static let OsmStandardReliefBase = ArcGISDesign(id: "osm_standard_relief_base")
    public static let OsmStreets = ArcGISDesign(id: "osm_streets")
    public static let OsmStreetsRelief = ArcGISDesign(id: "osm_streets_relief")
    public static let OsmLightGray = ArcGISDesign(id: "osm_light_gray")
    public static let OsmLightGrayBase = ArcGISDesign(id: "osm_light_gray_base")
    public static let OsmLightGrayLabels = ArcGISDesign(id: "osm_light_gray_labels")
    public static let OsmDarkGray = ArcGISDesign(id: "osm_dark_gray")
    public static let OsmDarkGrayBase = ArcGISDesign(id: "osm_dark_gray_base")
    public static let OsmDarkGrayLabels = ArcGISDesign(id: "osm_dark_gray_labels")
    public static let OsmStreetsReliefBase = ArcGISDesign(id: "osm_streets_relief_base")
    public static let OsmBlueprint = ArcGISDesign(id: "osm_blueprint")
    public static let OsmHybrid = ArcGISDesign(id: "osm_hybrid")
    public static let OsmHybridDetail = ArcGISDesign(id: "osm_hybrid_detail")
    public static let OsmNavigation = ArcGISDesign(id: "osm_navigation")
    public static let OsmNavigationDark = ArcGISDesign(id: "osm_navigation_dark")

    public static func Create(id: String, sources: [String] = []) -> ArcGISDesign {
        let known = all.first { $0.id == id }
        return known?.withElevationSources(sources) ?? ArcGISDesign(id: id, elevationSources: sources)
    }

    public static func toBasemapStyle(_ designType: ArcGISMapDesignType) -> Basemap.Style {
        switch designType.getValue() {
        case Streets.id: return .arcGISStreets
        case Imagery.id: return .arcGISImagery
        case ImageryStandard.id: return .arcGISImageryStandard
        case ImageryLabels.id: return .arcGISImageryLabels
        case LightGray.id: return .arcGISLightGray
        case LightGrayBase.id: return .arcGISLightGrayBase
        case LightGrayLabels.id: return .arcGISLightGrayLabels
        case DarkGray.id: return .arcGISDarkGray
        case DarkGrayBase.id: return .arcGISDarkGrayBase
        case DarkGrayLabels.id: return .arcGISDarkGrayLabels
        case Navigation.id: return .arcGISNavigation
        case NavigationNight.id: return .arcGISNavigationNight
        case StreetsNight.id: return .arcGISStreetsNight
        case StreetsRelief.id: return .arcGISStreetsRelief
        case Topographic.id: return .arcGISTopographic
        case Oceans.id: return .arcGISOceans
        case OceansBase.id: return .arcGISOceansBase
        case OceansLabels.id: return .arcGISOceansLabels
        case Terrain.id: return .arcGISTerrain
        case TerrainBase.id: return .arcGISTerrainBase
        case TerrainDetail.id: return .arcGISTerrainDetail
        case Community.id: return .arcGISCommunity
        case ChartedTerritory.id: return .arcGISChartedTerritory
        case ColoredPencil.id: return .arcGISColoredPencil
        case Nova.id: return .arcGISNova
        case ModernAntique.id: return .arcGISModernAntique
        case Midcentury.id: return .arcGISMidcentury
        case Newspaper.id: return .arcGISNewspaper
        case HillshadeLight.id: return .arcGISHillshadeLight
        case HillshadeDark.id: return .arcGISHillshadeDark
        case StreetsReliefBase.id: return .arcGISStreetsReliefBase
        case TopographicBase.id: return .arcGISTopographicBase
        case ChartedTerritoryBase.id: return .arcGISChartedTerritoryBase
        case ModernAntiqueBase.id: return .arcGISModernAntiqueBase
        case HumanGeography.id: return .arcGISHumanGeography
        case HumanGeographyBase.id: return .arcGISHumanGeographyBase
        case HumanGeographyDetail.id: return .arcGISHumanGeographyDetail
        case HumanGeographyLabels.id: return .arcGISHumanGeographyLabels
        case HumanGeographyDark.id: return .arcGISHumanGeographyDark
        case HumanGeographyDarkBase.id: return .arcGISHumanGeographyDarkBase
        case HumanGeographyDarkDetail.id: return .arcGISHumanGeographyDarkDetail
        case HumanGeographyDarkLabels.id: return .arcGISHumanGeographyDarkLabels
        case Outdoor.id: return .arcGISOutdoor
        case OsmStandard.id: return Basemap.Style.openOSMStyle
        case OsmStandardRelief.id: return Basemap.Style.openOSMStyleRelief
        case OsmStandardReliefBase.id: return Basemap.Style.openOSMStyleReliefBase
        case OsmStreets.id: return Basemap.Style.openStreets
        case OsmStreetsRelief.id: return Basemap.Style.openStreetsRelief
        case OsmLightGray.id: return Basemap.Style.openLightGray
        case OsmLightGrayBase.id: return Basemap.Style.openLightGrayBase
        case OsmLightGrayLabels.id: return Basemap.Style.openLightGrayLabels
        case OsmDarkGray.id: return Basemap.Style.openDarkGray
        case OsmDarkGrayBase.id: return Basemap.Style.openDarkGrayBase
        case OsmDarkGrayLabels.id: return Basemap.Style.openDarkGrayLabels
        case OsmStreetsReliefBase.id: return Basemap.Style.openStreetsReliefBase
        case OsmBlueprint.id: return Basemap.Style.openBlueprint
        case OsmHybrid.id: return Basemap.Style.openHybrid
        case OsmHybridDetail.id: return Basemap.Style.openHybridDetail
        case OsmNavigation.id: return Basemap.Style.openNavigation
        case OsmNavigationDark.id: return Basemap.Style.openNavigationDark
        default: return .arcGISStreets
        }
    }

    private static let all: [ArcGISDesign] = [
        Streets, Imagery, ImageryStandard, ImageryLabels, LightGray, LightGrayBase, LightGrayLabels,
        DarkGray, DarkGrayBase, DarkGrayLabels, Navigation, NavigationNight, StreetsNight,
        StreetsRelief, Topographic, Oceans, OceansBase, OceansLabels, Terrain, TerrainBase,
        TerrainDetail, Community, ChartedTerritory, ColoredPencil, Nova, ModernAntique,
        Midcentury, Newspaper, HillshadeLight, HillshadeDark, StreetsReliefBase, TopographicBase,
        ChartedTerritoryBase, ModernAntiqueBase, HumanGeography, HumanGeographyBase,
        HumanGeographyDetail, HumanGeographyLabels, HumanGeographyDark, HumanGeographyDarkBase,
        HumanGeographyDarkDetail, HumanGeographyDarkLabels, Outdoor, OsmStandard,
        OsmStandardRelief, OsmStandardReliefBase, OsmStreets, OsmStreetsRelief, OsmLightGray,
        OsmLightGrayBase, OsmLightGrayLabels, OsmDarkGray, OsmDarkGrayBase, OsmDarkGrayLabels,
        OsmStreetsReliefBase, OsmBlueprint, OsmHybrid, OsmHybridDetail, OsmNavigation,
        OsmNavigationDark,
    ]
}
