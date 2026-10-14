//
//  WristbandScannerView.swift
//  ProximiioGADKit
//
//  Camera scanner for the QR code on the back of the wristband. Uses VisionKit
//  `DataScannerViewController`, which requires camera access and a device with an
//  A12 Bionic chip or later. It is not available in the Simulator; the flow then offers
//  manual code entry only.
//
import AVFoundation
import SwiftUI
import VisionKit

struct WristbandScannerView: View {
    let onScan: (String) -> Void
    let onCancel: () -> Void
    let onEnterManually: () -> Void
    let onCameraDenied: () -> Void

    @State private var hasCameraAccess = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if hasCameraAccess, DataScannerViewController.isSupported {
                QRScanner(onScan: onScan).ignoresSafeArea()
            } else if !DataScannerViewController.isSupported {
                Text("Scanning is not available on this device.", bundle: .module)
                    .textStyle(.bodyMedium)
                    .foregroundStyle(Palette.white)
            }
            VStack(spacing: 24) {
                Text("Hold the QR code on the back of your wristband inside the frame", bundle: .module)
                    .textStyle(.bodyMedium)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.white)
                    .padding(.horizontal, 40)
                    .padding(.top, 48)
                Spacer()
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Palette.white.opacity(0.6), lineWidth: 1)
                    .frame(width: 260, height: 260)
                Spacer()
                Button(String(localized: "Enter code manually", bundle: .module), action: onEnterManually)
                    .buttonStyle(.textAction)
                    .foregroundStyle(Palette.white)
                Button(String(localized: "Cancel", bundle: .module), action: onCancel)
                    .buttonStyle(.primary)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .task { await requestCameraAccess() }
    }

    private func requestCameraAccess() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasCameraAccess = true
        case .notDetermined:
            hasCameraAccess = await AVCaptureDevice.requestAccess(for: .video)
            if !hasCameraAccess { onCameraDenied() }
        default:
            onCameraDenied()
        }
    }
}

/// Reports the payload of the first recognised QR code.
private struct QRScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var hasReported = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(
            _ scanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !hasReported else { return }
            for case .barcode(let barcode) in addedItems {
                guard let payload = barcode.payloadStringValue else { continue }
                hasReported = true
                scanner.stopScanning()
                onScan(payload)
                return
            }
        }
    }
}
