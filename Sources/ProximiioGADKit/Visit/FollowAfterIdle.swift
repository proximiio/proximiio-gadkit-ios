//
//  FollowAfterIdle.swift
//  ProximiioGADKit
//
//  The journey map follows the visitor again when a gesture left the camera free and the camera
//  has not moved for `GADSettings.followsAgainAfterSeconds` (owner, 2026-11-27). The map library
//  reports the change to the free camera, not each gesture after it, so the camera is read at an
//  interval: a pan, a zoom or a rotation changes it, and the time counts from the last change.
//
import Foundation

struct FollowAfterIdle {
    /// The camera at one reading, rounded so that a still camera compares equal.
    struct Camera: Equatable {
        var latitude: Int64
        var longitude: Int64
        var zoom: Int
        var direction: Int

        /// About 1 cm, 0.01 of a zoom level and 0.5°.
        init(latitude: Double, longitude: Double, zoom: Double, direction: Double) {
            self.latitude = Int64((latitude * 1e7).rounded())
            self.longitude = Int64((longitude * 1e7).rounded())
            self.zoom = Int((zoom * 100).rounded())
            self.direction = Int((direction * 2).rounded())
        }
    }

    /// Seconds between two readings of the camera.
    static let interval: TimeInterval = 0.5

    private var camera: Camera?
    /// When the free camera last moved, or was first read free.
    private var stillSince: TimeInterval?

    /// One reading at `now` (seconds of a monotonic clock). `true` when the map takes the follow
    /// again: the camera is free, it has been still for `seconds`, and `isAllowed`. `seconds` of 0
    /// or less never follows. While the camera follows, or `isAllowed` is `false`, the time starts
    /// again, so the follow comes `seconds` after the condition ends. Pure; covered by tests.
    mutating func reading(_ camera: Camera?, isFree: Bool, isAllowed: Bool, seconds: TimeInterval, now: TimeInterval) -> Bool {
        guard seconds > 0, isFree, isAllowed, let camera else {
            self.camera = nil
            stillSince = nil
            return false
        }
        guard camera == self.camera, let stillSince else {
            self.camera = camera
            stillSince = now
            return false
        }
        guard now - stillSince >= seconds else { return false }
        self.camera = nil
        self.stillSince = nil
        return true
    }
}
