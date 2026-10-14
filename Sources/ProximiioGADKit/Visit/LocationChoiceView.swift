//
//  LocationChoiceView.swift
//  ProximiioGADKit
//
//  Full-screen choice when the position is ambiguous (Figma nodes 6902:38047 EC04a,
//  6902:38073 EC04b, 6902:38099 EC04c, 6902:38362 EC04d): header with level and gallery and a
//  close button, a two-weight question, and options as frosted glass cards.
//
import SwiftUI

struct LocationChoice: Identifiable, Equatable {
    struct Option: Identifiable, Equatable {
        enum Action: Equatable {
            /// Make this journey stop the active one.
            case activateStop(String)
            /// The visitor is in this gallery.
            case gallery(String)
            /// None of the options; close the prompt.
            case somewhereElse
        }

        var id: String
        var title: String
        var subtitle: String?
        var action: Action

        static let somewhereElse = Option(id: "somewhere-else", title: String(localized: "Somewhere else", bundle: .module), action: .somewhereElse)
    }

    var id: String { kind }
    var kind: String
    var questionLight: LocalizedStringKey?
    var questionBold: LocalizedStringKey
    var caption: LocalizedStringKey?
    var options: [Option]

    init(kind: String, questionLight: LocalizedStringKey? = nil, questionBold: LocalizedStringKey,
         caption: LocalizedStringKey? = nil, options: [Option]) {
        self.kind = kind
        self.questionLight = questionLight
        self.questionBold = questionBold
        self.caption = caption
        self.options = options
    }

    static func == (lhs: LocationChoice, rhs: LocationChoice) -> Bool {
        lhs.kind == rhs.kind && lhs.options == rhs.options
    }
}

struct LocationChoiceView: View {
    let choice: LocationChoice
    let level: String?
    let gallery: String?
    let onPick: (LocationChoice.Option) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            AuroraBackground()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let level { Text(level).textStyle(.bodyExtraSmall).textCase(.uppercase) }
                        if let gallery { Text(gallery).textStyle(.largeBodyBold) }
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.iconGlass)
                    .accessibilityLabel(Text("Close", bundle: .module))
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 0) {
                    if let light = choice.questionLight {
                        Text(light, bundle: .module).font(GADFonts.custom("GuggenheimSansDisplay-Regular", size: 24, relativeTo: .title))
                    }
                    Text(choice.questionBold, bundle: .module).textStyle(.h1Bold)
                }
                .padding(.top, 100)

                if let caption = choice.caption {
                    Text(caption, bundle: .module).textStyle(.bodySmallRegular).padding(.top, 50)
                }

                VStack(spacing: 12) {
                    ForEach(choice.options) { option in
                        Button { onPick(option) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(option.title).textStyle(.bodyMedium)
                                if let subtitle = option.subtitle {
                                    Text(subtitle).textStyle(.bodySmallRegular)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, option.subtitle == nil ? 20 : 18)
                            .glassSurface(RoundedRectangle(cornerRadius: 12), strength: .frosted)
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                }
                .padding(.top, choice.caption == nil ? 40 : 15)
                Spacer()
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 40)
        }
    }
}

/// Soft prompt when the position is uncertain near the active stop (EC04d): the stop's
/// title, and buttons to confirm or to pick manually.
struct LowConfidencePrompt: View {
    let stop: String
    let onConfirm: () -> Void
    let onNotHere: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("PROBABLY AT", bundle: .module).textStyle(.caption)
            Text(stop).textStyle(.h1Bold)
            Text("Your position is uncertain here.", bundle: .module).textStyle(.bodySmallRegular).padding(.bottom, 20)
            Button(String(localized: "That's right", bundle: .module), action: onConfirm).buttonStyle(.primary)
            Button(String(localized: "Not here", bundle: .module), action: onNotHere).buttonStyle(.textAction)
        }
        .overlaySheetStyle()
    }
}

/// Pressed state of the design's cards: scale to 0.95.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
