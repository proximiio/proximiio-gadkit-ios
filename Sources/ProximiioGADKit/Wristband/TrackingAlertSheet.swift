//
//  TrackingAlertSheet.swift
//  ProximiioGADKit
//
//  Sheets shown during a visit when positions stop (Figma "Wristband", nodes 9330:84838
//  and 9330:84866), and when the wristband session ends.
//
import SwiftUI

struct TrackingAlertSheet: View {
    let health: TrackingHealth
    /// "Gallery 2, 9:38".
    let lastSeen: String?
    /// Number of the active stop, for "Your journey is saved at Stop 3".
    let activeStopNumber: Int?
    let canRouteToDesk: Bool
    let onSearchAgain: () -> Void
    let onRouteToDesk: () -> Void
    let onPickStop: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 44, height: 44)
                .background(Palette.white, in: Circle())
                .overlay(Circle().strokeBorder(Palette.red.opacity(0.4), lineWidth: 6).blur(radius: 3))
                .padding(.bottom, 10)
                .accessibilityHidden(true)
            switch health {
            case .stoppedResponding: stoppedResponding
            default: lostPlace
            }
        }
        .overlaySheetStyle()
    }

    @ViewBuilder private var stoppedResponding: some View {
        Text("Your wristband has stopped responding", bundle: .module).textStyle(.h1Bold)
        if let activeStopNumber {
            Text("Its battery may have run out. Your journey is saved at Stop \(activeStopNumber) - nothing is lost.", bundle: .module)
                .textStyle(.bodySmallRegular)
        } else {
            Text("Its battery may have run out. Your journey is saved - nothing is lost.", bundle: .module).textStyle(.bodySmallRegular)
        }
        if let lastSeen {
            HStack {
                Text("Last Seen", bundle: .module).textStyle(.bodySmallBold)
                Spacer()
                Text(lastSeen).textStyle(.bodySmallRegular)
            }
            .padding(20)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.ink, lineWidth: 1.5))
            .padding(.vertical, 10)
        }
        Button(String(localized: "Search Again", bundle: .module), action: onSearchAgain).buttonStyle(.primary).padding(.top, 10)
        if canRouteToDesk {
            Button(String(localized: "Swap it at the Welcome Desk", bundle: .module), action: onRouteToDesk).buttonStyle(.textAction)
        }
    }

    @ViewBuilder private var lostPlace: some View {
        Text("We’ve lost your place in the room", bundle: .module).textStyle(.h1Bold)
        Text("Walk a few steps toward the centre of the gallery and we’ll find you again.", bundle: .module)
            .textStyle(.bodySmallRegular)
        Button(String(localized: "Pick my stop manually", bundle: .module), action: onPickStop).buttonStyle(.primary).padding(.top, 20)
        Button(String(localized: "Dismiss", bundle: .module), action: onDismiss).buttonStyle(.textAction)
    }
}

/// Shown during a visit when the wristband session ended, for example after another phone
/// took the wristband over. No Figma frame exists for it yet.
struct WristbandEndedSheet: View {
    /// `WristbandCopy.notice(for:)`.
    let notice: String
    let onConnect: () -> Void
    let onBackToHub: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 44, height: 44)
                .background(Palette.white, in: Circle())
                .overlay(Circle().strokeBorder(Palette.red.opacity(0.4), lineWidth: 6).blur(radius: 3))
                .padding(.bottom, 10)
                .accessibilityHidden(true)
            Text("Your wristband is no longer connected", bundle: .module).textStyle(.h1Bold)
            Text(notice).textStyle(.bodySmallRegular)
            Button(String(localized: "Connect a wristband", bundle: .module), action: onConnect).buttonStyle(.primary).padding(.top, 20)
            Button(String(localized: "Back to Hub", bundle: .module), action: onBackToHub).buttonStyle(.textAction)
        }
        .overlaySheetStyle()
    }
}
