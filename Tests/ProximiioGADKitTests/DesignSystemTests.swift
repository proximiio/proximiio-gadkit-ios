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
