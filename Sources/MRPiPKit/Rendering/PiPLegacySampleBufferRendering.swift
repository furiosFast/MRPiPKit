//
//  PiPLegacySampleBufferRendering.swift
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

/// Before iOS 27: buffers go straight to the layer's renderer and display immediately.
@available(iOS, introduced: 18, deprecated: 27)
@MainActor
final class PiPLegacySampleBufferRendering: PiPSampleBufferRendering {
    private let renderer: AVSampleBufferVideoRenderer
    var error: Error? {
        renderer.error
    }

    let displaysImmediately = true

    init(layer: AVSampleBufferDisplayLayer) {
        renderer = layer.sampleBufferRenderer
    }

    func enqueue(_ buffer: sending CMSampleBuffer) -> Bool {
        if renderer.status == .failed {
            renderer.flush()
        }
        renderer.enqueue(buffer)
        return true
    }

    /// Immediate display has no playback clock; keeping the renderer retains its current image.
    func pause() {}

    func stop() async {
        await renderer.flush(removingDisplayedImage: true)
    }
}
