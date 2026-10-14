//
//  WristbandConnectionScreen.swift
//  ProximiioGADKit
//
//  The host app's screen for "Connect a wristband" in `VisitView`, in place of
//  `WristbandPairingView`. A host app with its own QR scanner sets it with
//  `wristbandConnectionScreen(_:)` and binds with `WristbandSession.connect(code:)`.
//
import SwiftUI

private struct WristbandConnectionScreenKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (_ close: @escaping @MainActor () -> Void) -> AnyView)? = nil
}

extension EnvironmentValues {
    var wristbandConnectionScreen: (@MainActor @Sendable (_ close: @escaping @MainActor () -> Void) -> AnyView)? {
        get { self[WristbandConnectionScreenKey.self] }
        set { self[WristbandConnectionScreenKey.self] = newValue }
    }
}

extension View {
    /// The screen that the `VisitView`s in this view show for "Connect a wristband" after the
    /// wristband session ended, in place of `WristbandPairingView`. `content` gets a closure that
    /// closes the screen. When it closes with an active session, `VisitView` reopens the
    /// wristband's position stream; without one, the "wristband no longer connected" sheet
    /// shows again.
    public func wristbandConnectionScreen<Content: View>(
        @ViewBuilder _ content: @escaping @MainActor @Sendable (_ close: @escaping @MainActor () -> Void) -> Content
    ) -> some View {
        environment(\.wristbandConnectionScreen) { close in AnyView(content(close)) }
    }
}
