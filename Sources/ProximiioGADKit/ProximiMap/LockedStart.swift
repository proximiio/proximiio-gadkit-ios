//
//  LockedStart.swift
//  ProximiioGADKit
//
//  A map that started while the phone was locked starts again at the unlock.
//
//  Source: field log of a host app, 2026-11-21 (iPhone 16, map 6.0.0-beta.66, report "map became
//  blank"). The host app created its journey map twice within 2 s while the phone was locked. Both
//  maps took the organisation's style in the same 10 ms, 75 s later, which is the map library's
//  path for a style it could not store on a locked phone. The map that stayed never drew the venue
//  (`closed 590.36 s before drawn`). A new start of the app drew it in 0.42 s. On a locked phone the
//  files of an app with complete data protection cannot be read or written, the map's cache
//  included. The blank map was not reproduced; the start while locked is inferred from the log.
//
import Foundation

enum LockedStart {
    /// Whether a screen starts again when the phone is unlocked. Pure; covered by tests.
    static func startsAgain(startedWhileLocked: Bool, settings: GADSettings?) -> Bool {
        startedWhileLocked && (settings ?? .standard).restartsMapAfterUnlock
    }
}
