//
//  VisitActivityAttributes.swift
//  ProximiioGADLiveActivity
//
//  The Live Activity of a visit (Figma "Live Updates / Activities", node 11737:49231): the
//  current step, "Stop N of M" and the next instruction. Updated by `VisitLiveActivity` in
//  ProximiioGADKit in the app; drawn by `VisitActivityWidget` in the widget extension.
//
import ActivityKit
import Foundation

public struct VisitActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        /// "Gallery 101", "Welcome to the museum", "Journey complete".
        public var title: String
        /// "Stop 1 of 12".
        public var progress: String
        /// "Turn left in 50 m", or empty.
        public var instruction: String
        /// "L1", or empty.
        public var level: String
        public var isFinished: Bool

        public init(title: String, progress: String, instruction: String, level: String, isFinished: Bool) {
            self.title = title
            self.progress = progress
            self.instruction = instruction
            self.level = level
            self.isFinished = isFinished
        }
    }

    /// "Your journey".
    public var journeyTitle: String

    public init(journeyTitle: String) {
        self.journeyTitle = journeyTitle
    }
}
