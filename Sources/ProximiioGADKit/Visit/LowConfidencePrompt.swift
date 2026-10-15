//
//  LowConfidencePrompt.swift
//  ProximiioGADKit
//
//  "Probably at …" (Figma node 6902:38362, EC04d).
//
import SwiftUI

/// Soft prompt when the position is uncertain near the active stop (EC04d): the stop's
/// title, and buttons to confirm or to close it.
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
