//
//  PiPSampleBufferReceiverRendering.swift
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

/// iOS 27 and later: a receiver on a render synchronizer, whose teardown is asynchronous.
@available(iOS 27, *)
@MainActor
final class PiPSampleBufferReceiverRendering: PiPSampleBufferRendering {
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private var receiver: AVSampleBufferVideoRenderer.Receiver?
    private(set) var error: Error?
    let displaysImmediately = false

    init(layer: AVSampleBufferDisplayLayer) {
        receiver = synchronizer.sampleBufferReceiver(adding: layer.sampleBufferRenderer)
        synchronizer.delaysRateChangeUntilHasSufficientMediaData = false
        synchronizer.setRate(1, time: CMClockGetTime(CMClockGetHostTimeClock()))
    }

    func enqueue(_ buffer: sending CMSampleBuffer) -> Bool {
        guard let receiver else { return false }
        // PiPSampleBuffer makes ready buffers. Only the small interface image is transferred here.
        switch receiver.enqueueImmediately(CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(unsafeBuffer: buffer)) {
            case .enqueued, .enqueuedWithDecodeFailures:
                return true
            case .cancelledDueToFlush:
                return false
            case let .cancelledDueToFlushRequiredToResume(error):
                self.error = error
                receiver.flush()
                return false
            case let .cancelledDueToError(error):
                self.error = error
                return false
            @unknown default:
                return false
        }
    }

    func pause() {
        // Freeze the last displayed image without flushing it during AVKit's closing animation.
        synchronizer.rate = 0
    }

    func stop() async {
        pause()
        guard let receiver else { return }
        self.receiver = nil
        await receiver.flush(removingDisplayedImage: true)
        _ = await synchronizer.removeReceiver(receiver, at: .invalid)
    }
}
