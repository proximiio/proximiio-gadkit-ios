//
//  DesignSystemTests.swift
//  ProximiioGADKitTests
//
import Testing
import UIKit
@_spi(GADApp) @testable import ProximiioGADKit

@MainActor
struct DesignSystemTests {
    /// Every text style resolves to a font file that the package bundles and registers.
    @Test(arguments: TextStyle.allCases)
    func everyTextStyleFontIsBundled(_ style: TextStyle) {
        GADFonts.register()
        #expect(UIFont(name: style.postScriptName, size: style.size) != nil, "\(style.postScriptName) is not registered")
    }

    @Test func stylesUseTheDisplayFamilyWithFigmaWeights() {
        #expect(TextStyle.cardTitle.postScriptName == "GuggenheimSansDisplay-SemiBold")
        #expect(TextStyle.h1Bold.postScriptName == "GuggenheimSansDisplay-Bold")
        #expect(TextStyle.bodyMedium.postScriptName == "GuggenheimSansDisplay-Medium")
        #expect(TextStyle.caption.tracking > 0)
    }

    @Test(arguments: ["IconCafe", "IconSearch", "IconCafeMarker", "YouAreHere"])
    func iconAssetsExist(_ name: String) {
        #expect(UIImage(named: name, in: .module, with: nil) != nil)
    }

    @Test func theMapSpinnerStaysUntilTheVenueIsDrawn() {
        #expect(MapLoadingSpinner.isShown(featureCount: 0, lastError: nil, hasTimedOut: false, isBusy: false))
        #expect(!MapLoadingSpinner.isShown(featureCount: 120, lastError: nil, hasTimedOut: false, isBusy: false))
        #expect(!MapLoadingSpinner.isShown(featureCount: 0, lastError: "style", hasTimedOut: false, isBusy: false))
        #expect(!MapLoadingSpinner.isShown(featureCount: 0, lastError: nil, hasTimedOut: true, isBusy: false))
        #expect(MapLoadingSpinner.isShown(featureCount: 120, lastError: nil, hasTimedOut: true, isBusy: true))
        #expect(GADSettings.standard.mapLoadingTimeout == 20)
    }
}

/// PM, Monday "Floorplan disappears zometimes", 2026-10-27.
@MainActor
struct MapDiagnosticsTests {
    @Test func theLineNamesTheMapStateAndTheZoomIsRoundedToAHalf() {
        #expect(MapDiagnostics.Snapshot.rounded(zoom: 20.74) == 20.5)
        #expect(MapDiagnostics.Snapshot.rounded(zoom: 20.76) == 21)
        #expect(MapDiagnostics.Snapshot.rounded(zoom: nil) == nil)
        var snapshot = MapDiagnostics.Snapshot(features: 968, dropped: 16, error: "16 features left out", style: "cache",
                                               level: 1, zoom: 19, isCameraReady: true)
        snapshot.name = "journey"
        #expect(snapshot.line == "map state journey: features 968 · dropped 16 · style cache · L1 · zoom 19.0 · camera ready true · error 16 features left out")
    }

    /// Map 6.0.0-beta.55 names the style's fonts the glyph server does not have.
    @Test func theLineNamesTheMissingFonts() {
        var snapshot = MapDiagnostics.Snapshot(features: 968, dropped: 0, error: nil, style: "organization",
                                               level: 1, zoom: 20, isCameraReady: true,
                                               missingFonts: ["Guggenheim Sans Bold", "Open Sans Bold"])
        snapshot.name = "museum"
        #expect(snapshot.line == "map state museum: features 968 · dropped 0 · style organization · L1 · zoom 20.0 · camera ready true · missing fonts Guggenheim Sans Bold, Open Sans Bold")
    }

    /// The selection follows the finger and stays inside the control (Monday "Native elements",
    /// 2026-10-28 evening).
    @Test func theMapListSelectionSlidesWithTheFinger() {
        #expect(MapListToggle.selectionOffset(showsList: false, slide: 30, width: 71) == 30)
        #expect(MapListToggle.selectionOffset(showsList: false, slide: -30, width: 71) == 0)
        #expect(MapListToggle.selectionOffset(showsList: true, slide: -50, width: 71) == 21)
        #expect(MapListToggle.selectionOffset(showsList: true, slide: 30, width: 71) == 71)
        // A tap picks the part under the finger; a slide the part the selection ends over.
        #expect(MapListToggle.showsList(afterSlide: 2, at: 100, showsList: false, width: 71))
        #expect(!MapListToggle.showsList(afterSlide: 0, at: 20, showsList: true, width: 71))
        #expect(MapListToggle.showsList(afterSlide: 40, at: 20, showsList: false, width: 71))
        #expect(!MapListToggle.showsList(afterSlide: 30, at: 20, showsList: false, width: 71))
        #expect(!MapListToggle.showsList(afterSlide: -50, at: 120, showsList: true, width: 71))
    }

    /// The map shows the venue when its first venue style, its features and the camera are all
    /// there (user, 2026-10-28).
    @Test func theTimingNamesEachStepAndTheDrawnFrame() {
        var timing = MapDiagnostics.Timing(name: "explore")
        timing.styles = [.init(source: "fallback(reason: \"x\")", isVenue: false, seconds: 0.1),
                         .init(source: "cache", isVenue: true, seconds: 0.412)]
        timing.features = 968
        timing.featuresSeconds = 2.104
        #expect(timing.shownSeconds == nil)
        #expect(timing.line(closedSeconds: 2.5) == "map timing explore: style fallback(reason: \"x\") 0.10 s · style cache 0.41 s · features 968 2.10 s · closed 2.50 s before drawn")
        timing.cameraSeconds = 1.9
        #expect(timing.shownSeconds == 2.104)
        #expect(timing.line(closedSeconds: 2.5) == "map timing explore: style fallback(reason: \"x\") 0.10 s · style cache 0.41 s · features 968 2.10 s · camera ready 1.90 s · shown 2.10 s · closed 2.50 s before drawn")
        #expect(MapDiagnostics.Timing(name: "journey").line(closedSeconds: 0.05) == "map timing journey: closed 0.05 s before drawn")
        timing.drawnSeconds = 2.6
        timing.openSeconds = 1.02
        #expect(timing.line().hasSuffix(" · shown 2.10 s · drawn 2.60 s, 3.62 s after open()"))
    }
}
