//
//  PiPSessionPhase.swift
//  MRPiPKit
//
//  Created by Marco Ricca on 09/10/2026
//
//  Created for MRPiPKit in 13/10/2026
//  Using Swift 6.4
//
//  Copyright © 2026 Fast-Devs Project by Marco Ricca. All rights reserved.
//

import Foundation

/// Where an AVKit session stands. Every lifecycle entry point of `PiPHostingViewController` switches on this single
/// value, so combinations such as "start confirmed while the receiver is being released" cannot be represented.
enum PiPSessionPhase: Equatable {
    /// No session: before the first start, or after teardown with at most an idle controller kept for reuse.
    case idle
    /// The session wants a PiP and prepares the first image; `pendingRequest` marks a start request deferred
    /// to the next main-queue turn.
    case preparing(pendingRequest: UUID?)
    /// `startPictureInPicture()` was called and AVKit has not begun the transition yet.
    case requested
    /// WillStart arrived: AVKit is presenting the window, and only DidStart, a start failure or the startup
    /// timeout end this phase.
    case starting
    /// The app stopped, or the startup timeout gave up, after WillStart: AVKit is still presenting, so the controller
    /// keeps itself, its delegate and its source until DidStart closes the window, a start failure, or one more
    /// startup timeout releases them.
    case cancellingStart
    /// DidStart arrived, or the startup timeout found the window already active.
    case active
    /// AVKit animates the window away; the source and its last image stay until DidStop.
    case stopping
    /// The video receiver is leaving its synchronizer; the stop completes when it has.
    case tearingDown

    /// The session renders images and reacts to readiness changes.
    var isLive: Bool {
        switch self {
            case .preparing, .requested, .starting, .active: true
            case .idle, .cancellingStart, .stopping, .tearingDown: false
        }
    }

    /// AVKit holds a start request it has neither confirmed nor rejected.
    var hasRequestedStart: Bool {
        self == .requested || self == .starting
    }

    /// The owner may detach immediately: the controller keeps itself alive until teardown ends.
    var isClosing: Bool {
        self == .cancellingStart || self == .stopping || self == .tearingDown
    }
}
