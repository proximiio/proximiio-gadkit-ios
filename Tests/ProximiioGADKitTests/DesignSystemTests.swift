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
}
