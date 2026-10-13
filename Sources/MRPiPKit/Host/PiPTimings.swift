//
//  PiPTimings.swift
//  MRPiPKit
//
//  Created by Marco Ricca on 13/10/2026
//
//  Created for MRPiPKit in 13/10/2026
//  Using Swift 6.4
//
//  Copyright © 2026 Fast-Devs Project by Marco Ricca. All rights reserved.
//

import QuartzCore

/// AVKit and the video receiver can stop answering: past these limits the lifecycle proceeds on its own.
enum PiPTimings {
    /// Time AVKit gets to begin and confirm a requested start, and an abandoned start to settle.
    static let startupTimeout: Duration = .seconds(5)
    /// Wait between renewals of a stop request AVKit has not confirmed.
    static let stopRenewalInterval: Duration = .seconds(5)
    /// Renewals before the session is released without AVKit's confirmation.
    static let stopRenewalLimit = 3
    /// Longest wait for the video receiver to leave its synchronizer.
    static let teardownTimeout: TimeInterval = 10
    /// Charts and gauges animate for one second after an update; static content needs no further snapshots.
    static let animationWindow: CFTimeInterval = 1
}
