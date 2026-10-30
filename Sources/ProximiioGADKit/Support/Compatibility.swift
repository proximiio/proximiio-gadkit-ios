//
//  Compatibility.swift
//  ProximiioGADKit
//
//  iOS 16 forms of the SwiftUI calls that need iOS 17. The package supports iOS 16.4 so that an
//  iPhone X (iOS 16.7 at most) runs the app (owner, 2026-10-30).
//
import SwiftUI

extension View {
    /// `onChange(of:initial:_:)` on iOS 17 and later. On iOS 16 `onChange(of:perform:)`, which
    /// passes the value before the change from the closure's capture, and with `initial` the
    /// action once when the view appears.
    @_spi(GADApp) @ViewBuilder
    public func onValueChange<Value: Equatable>(
        of value: Value,
        initial: Bool = false,
        _ action: @escaping (_ oldValue: Value, _ newValue: Value) -> Void
    ) -> some View {
        if #available(iOS 17, *) {
            onChange(of: value, initial: initial, action)
        } else {
            onChange(of: value) { [value] newValue in action(value, newValue) }
                .onAppear { if initial { action(value, value) } }
        }
    }

    /// `scrollClipDisabled()` on iOS 17 and later; nothing on iOS 16.
    @ViewBuilder
    func scrollClipDisabledIfAvailable() -> some View {
        if #available(iOS 17, *) {
            scrollClipDisabled()
        } else {
            self
        }
    }

    /// Space under a scroll view's content: `contentMargins` on iOS 17 and later, a bottom inset
    /// on iOS 16.
    @ViewBuilder
    func scrollContentBottomMargin(_ height: CGFloat) -> some View {
        if #available(iOS 17, *) {
            contentMargins(.bottom, height, for: .scrollContent)
        } else {
            safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: height) }
        }
    }
}
