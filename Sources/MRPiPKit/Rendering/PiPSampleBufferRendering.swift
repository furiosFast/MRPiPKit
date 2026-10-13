//
//  PiPSampleBufferRendering.swift
//  MRPiPKit
//
//  Created by Marco Ricca on 09/10/2026
//
//  Created for MRPiPKit in 13/10/2026
//  Using Swift 6.4
//
//  Copyright © 2026 Fast-Devs Project by Marco Ricca. All rights reserved.
//

import AVFoundation
import CoreMedia

/// Feeds the PiP source layer with image sample buffers. Older systems enqueue on the layer's renderer; iOS 27
/// replaces those APIs with a receiver attached to a render synchronizer.
@MainActor
protocol PiPSampleBufferRendering: Sendable {
    var error: Error? { get }
    /// Buffers carry the display-immediately attachment instead of following a playback clock.
    var displaysImmediately: Bool { get }
    func enqueue(_ buffer: sending CMSampleBuffer) -> Bool
    /// Freezes the current image for AVKit's closing animation.
    func pause()
    /// Flushes the image and detaches from the layer.
    func stop() async
}

/// The rendering path of the running system for a new session's layer.
@MainActor
func makePiPSampleBufferRendering(for layer: AVSampleBufferDisplayLayer) -> any PiPSampleBufferRendering {
    if #available(iOS 27, *) {
        return PiPSampleBufferReceiverRendering(layer: layer)
    }
    return PiPLegacySampleBufferRendering(layer: layer)
}
