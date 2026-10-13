//
//  PiPDisplayLink.swift
//  MRPiPKit
//
//  Created by Marco Ricca on 13/10/2026
//
//  Created for MRPiPKit in 13/10/2026
//  Using Swift 6.4
//
//  Copyright © 2026 Fast-Devs Project by Marco Ricca. All rights reserved.
//

import Foundation
import QuartzCore

/// The display link of the foreground animation frames.
@MainActor
final class PiPDisplayLink {
    private var link: CADisplayLink?

    var isRunning: Bool {
        link != nil
    }

    /// Starts at `framesPerSecond` unless it is already running. The common run-loop modes keep the frames flowing while
    /// a table in the app is scrolling (tracking mode).
    func start(framesPerSecond: Int, handler: @escaping (CADisplayLink) -> Void) {
        guard link == nil else { return }
        let link = CADisplayLink(target: PiPDisplayLinkTarget(handler: handler), selector: #selector(PiPDisplayLinkTarget.render(_:)))
        let rate = Float(max(1, framesPerSecond))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 1, maximum: rate, preferred: rate)
        self.link = link
        link.add(to: .main, forMode: .common)
    }

    func stop() {
        link?.invalidate()
        link = nil
    }
}

/// CADisplayLink retains its target: the target holds only the handler, which captures its owner weakly.
@MainActor
private final class PiPDisplayLinkTarget: NSObject {
    private let handler: (CADisplayLink) -> Void

    init(handler: @escaping (CADisplayLink) -> Void) {
        self.handler = handler
        super.init()
    }

    @objc func render(_ link: CADisplayLink) {
        handler(link)
    }
}
