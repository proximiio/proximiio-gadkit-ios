//
//  Components.swift
//  ProximiioGADKit
//
//  Small components from the Figma design system: the stop number badge (Card_Glass_2,
//  node 6902:46979), the outlined badge ("AR", node 6902:46804), the labelled input
//  (Input, node 6902:47661) and the design's icons.
//
import SwiftUI

/// Stop number badge (Figma journey list, node 11820:71364; PM review 2026-10-12): a 34 pt
/// circle, Body Medium. A pending stop is white with a 2 pt #EEEDED stroke. The next stop and a
/// stop being acted on (swiped) are filled red with a white number. A visited stop is white with
/// a red stroke. The circles match the map's journey stop markers (`MapStyle.journeyStops`).
struct StopNumberBadge: View {
    enum Emphasis { case normal, filled, visited }

    let number: Int
    var emphasis: Emphasis = .normal

    var body: some View {
        Text("\(number)", bundle: .module)
            .textStyle(.bodyMedium)
            .foregroundStyle(emphasis == .filled ? Palette.white : Palette.ink)
            .frame(width: 34, height: 34)
            .background(emphasis == .filled ? Palette.activeRed : Palette.white, in: Circle())
            .overlay(Circle().strokeBorder(emphasis == .normal ? Palette.badgeStroke : Palette.activeRed, lineWidth: 2))
    }
}

/// Outlined label such as "AR" or a floor "L2", or an outlined symbol such as the audio note
/// (Figma journey list): 1 pt ink stroke, 6 pt radius, SemiBold 10.
struct OutlineBadge: View {
    private let text: String?
    private let systemImage: String?

    init(text: String) {
        self.text = text
        systemImage = nil
    }

    init(systemImage: String) {
        text = nil
        self.systemImage = systemImage
    }

    var body: some View {
        Group {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
            } else {
                Text(text ?? "")
                    .font(GADFonts.custom("GuggenheimSansDisplay-SemiBold", size: 10, relativeTo: .caption2))
                    .tracking(0.6)
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 5)
        .frame(minWidth: 25, minHeight: 20)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.ink, lineWidth: 1))
    }
}

/// Labelled input field (Figma Input, node 6902:47661, as used on `sign-in`): Body Small
/// label, 60 pt field on the mint gradient, 12 pt radius, 1.5 pt white stroke and a soft
/// shadow; error is a #FF8686 stroke with a red label.
public struct LabeledField<Field: View>: View {
    /// Looked up in the host app's main bundle, like `Text(_:)`.
    let label: LocalizedStringKey
    var isError = false
    @ViewBuilder let field: Field

    public init(label: LocalizedStringKey, isError: Bool = false, @ViewBuilder field: () -> Field) {
        self.label = label
        self.isError = isError
        self.field = field()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .textStyle(.bodySmallRegular)
                .foregroundStyle(isError ? Palette.errorLabel : Palette.ink)
            field
                .textStyle(.bodyMedium)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 20)
                .frame(minHeight: 60)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Palette.inputFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12).fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color(hex: 0xD6D6D6), location: 0.16),
                                        .init(color: .white.opacity(0), location: 0.43),
                                        .init(color: Color(hex: 0xE7E7E7), location: 1.08),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .opacity(0.55)
                        )
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isError ? Palette.errorStroke : Palette.white, lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 2.5, x: 0, y: 3)
        }
    }
}

/// The design's icons (`icons-svg`, imported as vector assets).
enum GADIcon: String {
    case cafe = "IconCafe"
    case compass = "IconCompass"
    case elevator = "IconElevator"
    case info = "IconInfo"
    case maleToilet = "IconMaleToilet"
    case femaleToilet = "IconFemaleToilet"
    case prayerRoom = "IconPrayerRoom"
    case search = "IconSearch"
    case shop = "IconShop"
    case stairs = "IconStairs"

    /// The glyph, tinted with the foreground style.
    var image: Image { Image(rawValue, bundle: .module).renderingMode(.template) }

    /// The white circle variant used as a map marker, or `nil` for icons without one.
    var markerImageName: String? {
        switch self {
        case .compass, .search: nil
        default: rawValue + "Marker"
        }
    }
}
