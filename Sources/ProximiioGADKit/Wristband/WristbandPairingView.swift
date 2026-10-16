//
//  WristbandPairingView.swift
//  ProximiioGADKit
//
//  Screens of the "Connect your wristband" flow (Figma section "Wristband", node 9330:83108).
//  Copy follows the design, except where design/COPY-ISSUES.md lists a deviation.
//
import SwiftUI

@_spi(GADApp) public struct WristbandPairingView: View {
    @Bindable var pairing: WristbandPairing
    /// "Skip for now", "Back to Hub" and "Continue" all leave the flow.
    let onFinish: () -> Void

    public init(pairing: WristbandPairing, onFinish: @escaping () -> Void) {
        self.pairing = pairing
        self.onFinish = onFinish
    }

    public var body: some View {
        switch pairing.step {
        case .intro:
            intro
        case .scanning:
            WristbandScannerView(
                onScan: { code in Task { await pairing.submit(code: code) } },
                onCancel: pairing.cancelScanning,
                onEnterManually: pairing.enterCodeManually,
                onCameraDenied: pairing.cameraAccessDenied
            )
        case .manualEntry:
            WristbandCodeEntryView(pairing: pairing)
        case .looking:
            looking
        case .connected(let label):
            connected(label)
        case .failed(_, let message, let attempts):
            failed(message: message, attempts: attempts)
        case .cameraDenied:
            cameraDenied
        }
    }

    // MARK: Screens

    private var intro: some View {
        PairingScreen(symbol: "qrcode.viewfinder", titleLight: "Connect", titleBold: "your wristband") {
            Text("Your wristband tracks where you are in the galleries. Pair it now, or later when your journey begins.", bundle: .module)
        } actions: {
            Button(String(localized: "Scan QR code", bundle: .module), action: pairing.startScanning).buttonStyle(.primary)
            Button(String(localized: "Skip for now", bundle: .module), action: onFinish).buttonStyle(.textAction)
        }
    }

    private var looking: some View {
        PairingScreen(symbol: "dot.radiowaves.left.and.right", titleLight: "Looking for", titleBold: "your wristband", isPulsing: true) {
            Text("This usually takes a few seconds.", bundle: .module)
        } actions: {
            EmptyView()
        }
    }

    private func connected(_ label: String) -> some View {
        PairingScreen(symbol: "checkmark", titleLight: "Wristband", titleBold: "connected!") {
            Text("Keep it on your wrist - the galleries will pick it up as you walk through.", bundle: .module)
            WristbandStatusCard(label: label, status: "Paired")
        } actions: {
            Button(String(localized: "Continue", bundle: .module), action: onFinish).buttonStyle(.primary)
        }
    }

    /// `message` comes from `WristbandCopy` and names the reason. The repeated-failure
    /// variant adds the design's referral to a host and drops "Try again".
    private func failed(message: String, attempts: Int) -> some View {
        let isRepeated = attempts > 1
        return PairingScreen(symbol: "exclamationmark", titleLight: "We couldn’t connect", titleBold: "your wristband") {
            Text(message)
            if isRepeated {
                Text("Please find a host that can help pair it for you.", bundle: .module)
            }
        } actions: {
            if !isRepeated {
                Button(String(localized: "Try again", bundle: .module)) { Task { await pairing.retry() } }.buttonStyle(.primary)
            }
            Button(String(localized: "Back to Hub", bundle: .module), action: onFinish).buttonStyle(.textAction)
        }
    }

    private var cameraDenied: some View {
        PairingScreen(symbol: "exclamationmark", titleLight: "Camera", titleBold: "permission denied") {
            Text("Allow camera access in Settings to scan your wristband, or enter its code.", bundle: .module)
        } actions: {
            Button(String(localized: "Go to Settings", bundle: .module)) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.primary)
            Button(String(localized: "Enter code manually", bundle: .module), action: pairing.enterCodeManually).buttonStyle(.textAction)
            Button(String(localized: "Back to Hub", bundle: .module), action: onFinish).buttonStyle(.textAction)
        }
    }
}

// MARK: - Building blocks

/// Layout shared by the pairing screens (Figma "Wristband", nodes 10874:96775 and
/// 9330:85003): a 180 pt icon with a soft red ring, the two-weight 32 pt title, Body Small
/// text 322 pt wide, and the actions near the bottom.
private struct PairingScreen<Content: View, Actions: View>: View {
    let symbol: String
    let titleLight: LocalizedStringKey
    let titleBold: LocalizedStringKey
    var isPulsing = false
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 0) {
                Spacer().frame(height: 110)
                IconRing(symbol: symbol, isPulsing: isPulsing)
                VStack(spacing: 20) {
                    VStack(spacing: 0) {
                        Text(titleLight, bundle: .module).font(GADFonts.custom("GuggenheimSansDisplay-Regular", size: 32, relativeTo: .largeTitle))
                        Text(titleBold, bundle: .module).font(GADFonts.custom("GuggenheimSansDisplay-Bold", size: 32, relativeTo: .largeTitle))
                    }
                    VStack(spacing: 16) { content }
                        .textStyle(.bodySmallRegular)
                }
                .multilineTextAlignment(.center)
                .frame(width: 322)
                .padding(.top, 20)
                Spacer()
                VStack(spacing: 28) { actions }
                    .frame(width: 322)
                    .padding(.bottom, 6)
            }
            .foregroundStyle(Palette.ink)
        }
    }
}

/// 180 pt mark: the symbol in a white circle inside a blurred red ring.
private struct IconRing: View {
    let symbol: String
    let isPulsing: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.red.opacity(0.28), lineWidth: 22)
                .blur(radius: 14)
                .frame(width: 140, height: 140)
                .scaleEffect(pulse ? 1.12 : 1)
            Circle()
                .stroke(Palette.red.opacity(0.18), lineWidth: 8)
                .blur(radius: 4)
                .frame(width: 104, height: 104)
            if symbol == "qrcode.viewfinder" {
                // Phone with a QR code, as drawn in the design.
                ZStack {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.ink, lineWidth: 2).frame(width: 34, height: 58)
                    Image(systemName: "qrcode").font(.system(size: 16, weight: .regular)).offset(y: -5)
                }
            } else {
                Circle().fill(Palette.white.opacity(0.6)).frame(width: 60, height: 60)
                Image(systemName: symbol).font(.system(size: 22, weight: .regular))
            }
        }
        .frame(width: 180, height: 180)
        .accessibilityHidden(true)
        .onAppear {
            guard isPulsing else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever()) { pulse = true }
        }
    }
}

/// "Wristband 7KQ4M2 · Paired" (Figma Card_Glass_2 outline variant): 1.5 pt ink stroke.
/// `label` is the code as scanned or typed.
private struct WristbandStatusCard: View {
    let label: String
    let status: LocalizedStringKey

    var body: some View {
        HStack {
            Text("Wristband \(label)", bundle: .module).textStyle(.bodySmallBold)
            Spacer()
            Text(status, bundle: .module).textStyle(.bodySmallRegular)
        }
        .padding(20)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.ink, lineWidth: 1.5))
    }
}

/// "Enter your wristband code". The design references this screen; it is not drawn yet.
struct WristbandCodeEntryView: View {
    @Bindable var pairing: WristbandPairing
    @State private var code: String
    @FocusState private var isFocused: Bool

    init(pairing: WristbandPairing) {
        self.pairing = pairing
        _code = State(initialValue: pairing.enteredCode)
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(alignment: .leading, spacing: 16) {
                Text("Enter your wristband code", bundle: .module).textStyle(.h1Bold)
                Text("The code is printed on the wristband.", bundle: .module).textStyle(.bodySmallRegular)
                TextField(String(localized: "Wristband code", bundle: .module), text: $code)
                    .textStyle(.bodyMedium)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .padding(16)
                    .background(Palette.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(pairing.invalidCodeMessage == nil ? Palette.inputStroke : Palette.errorStroke)
                    )
                if let message = pairing.invalidCodeMessage {
                    Text(message).textStyle(.bodyExtraSmall).foregroundStyle(Palette.errorLabel)
                }
                Spacer()
                Button(String(localized: "Connect", bundle: .module)) { Task { await pairing.submit(code: code) } }
                    .buttonStyle(.primary)
                    .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(String(localized: "Cancel", bundle: .module), action: pairing.cancelScanning)
                    .buttonStyle(.textAction)
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(Palette.ink)
            .padding(24)
        }
        .onAppear { isFocused = true }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Intro") {
    WristbandPairingView(pairing: DemoPairing.make(succeeds: true), onFinish: {})
}
#endif
