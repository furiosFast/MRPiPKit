//
//  PiPHostingViewController+Stopping.swift
//  MRPiPKit
//
//  Created by Marco Ricca on 13/10/2026
//
//  Created for MRPiPKit in 13/10/2026
//  Using Swift 6.4
//
//  Copyright © 2026 Fast-Devs Project by Marco Ricca. All rights reserved.
//

import AVKit
import Combine
import UIKit

/// Ending a session: AVKit's closing animation, the fallbacks when it does not answer, and the image pipeline teardown.
extension PiPHostingViewController {
    /// The app asked for the stop: AVKit's close emits no exit event, and no automatic start recovery follows.
    func markExplicitStop() {
        explicitStop = true
        startupRecoveryID = nil
    }

    /// Ends rendering and readiness tracking; callers move the phase out of the live states first.
    func stopImageUpdates() {
        cancelStartupTimeout()
        readinessObservers.removeAll()
        stopForegroundRendering()
    }

    func beginStopping() {
        guard !phase.isClosing else { return }
        phase = .stopping
        stopImageUpdates()
        transitionDidChange?(true)
        sampleBufferRendering?.pause()
        // There is no inline player to restore. Hide that animation target while
        // keeping the layer and its last frame alive until AVKit confirms DidStop.
        sourceView.isHidden = true
        // DidStop owns teardown. Recover from a missing callback only once AVKit is confirmed inactive.
        stopTimeoutTask = Task { [weak self] in
            var renewals = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: PiPTimings.stopRenewalInterval) } catch { return }
                guard let self, phase == .stopping else { return }
                if controller?.isPictureInPictureActive == true, renewals < PiPTimings.stopRenewalLimit {
                    renewals += 1
                    PiPKitLog.d("PiP AVKit: chiusura ancora in corso, rinnovo della richiesta di arresto (\(renewals)/\(PiPTimings.stopRenewalLimit))")
                    if let controller {
                        requestWindowClose(controller)
                    }
                    continue
                }
                // Past the renewals AVKit never confirmed: release the source anyway rather than lock every switch,
                // and discard the controller whose stop callback never arrived.
                PiPKitLog.d(controller?.isPictureInPictureActive == true ? "PiP AVKit: nessuna conferma di chiusura, rilascio forzato" : "PiP AVKit: sessione inattiva senza callback di chiusura")
                releaseWithoutStopConfirmation()
                return
            }
        }
        // On device AVKit answered no stop request made in background, with the screen locked or another app in front:
        // the window stayed on screen, black, with every PiP switch locked until the forced release, which closes it.
        backgroundStopObservation = NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, phase == .stopping else { return }
                PiPKitLog.d("PiP AVKit: app in background durante la chiusura, rilascio senza attendere AVKit")
                releaseWithoutStopConfirmation()
            }
    }

    /// Asks AVKit to close the window of a session that is stopping. In background AVKit answers no stop request: the
    /// observer in `beginStopping()` covers a later move to the background, this check a stop that starts there.
    func requestWindowClose(_ pictureInPictureController: AVPictureInPictureController) {
        pictureInPictureController.stopPictureInPicture()
        guard phase == .stopping, isAppInBackground else { return }
        PiPKitLog.d("PiP AVKit: arresto con l'app in background, rilascio senza attendere AVKit")
        releaseWithoutStopConfirmation()
    }

    /// Ends a stop AVKit has not confirmed: releasing the source and the controller closes the window, and that
    /// controller is never reused because its stop callback did not arrive.
    func releaseWithoutStopConfirmation() {
        canReuseController = false
        finishStopping()
    }

    func finishStopping() {
        let shouldExit = !explicitStop
        releaseRendering()
        if shouldExit {
            exitSubject.send()
        }
    }

    func releaseRendering() {
        guard phase != .tearingDown else { return }
        // Tearing down keeps this session alive and holds the slot's stop completion until the receiver has
        // actually left the synchronizer: decoder teardown is asynchronous.
        phase = .tearingDown
        transitionDidChange?(true)
        stopImageUpdates()
        stopTimeoutTask?.cancel()
        stopTimeoutTask = nil
        backgroundStopObservation = nil
        // Invalidate AVKit's source before releasing its frames, including a start with no callback.
        // Clearing the delegate also prevents old teardown events from reaching a new session.
        controller?.delegate = nil
        controller?.canStartPictureInPictureAutomaticallyFromInline = false
        controller?.contentSource = nil
        hasEnqueuedImage = false
        Task { [self] in
            let finished = await awaitWithTimeout(PiPTimings.teardownTimeout) { [sampleBufferRendering] in
                await sampleBufferRendering?.stop()
            }
            if !finished {
                // The old receiver may still be leaving its synchronizer: never hand this layer to a new session.
                canReuseController = false
                PiPKitLog.d("PiP AVKit: rilascio del receiver oltre il limite, pipeline abbandonata e controller non riutilizzabile")
            }
            finishReleasingRendering()
        }
    }

    func finishReleasingRendering() {
        sampleBufferRendering = nil
        displayLayer.removeFromSuperlayer()
        sourceView.removeFromSuperview()
        if !canReuseController {
            controller = nil
            displayLayer = AVSampleBufferDisplayLayer()
        }
        // Confirmed stops retain only the idle controller/layer. The receiver, source,
        // delegate, images, observers and animation link have all been released.
        bitmapRenderer.reset()
        animatesContinuously = false
        let completions = stopCompletions
        stopCompletions.removeAll()
        // Back to idle: the controller stops retaining itself, and the slot may keep it for the next start.
        phase = .idle
        // The session has settled, unless the silent-start recovery restarts it right away from the completions below.
        if explicitStop || startupRecoveryID == nil {
            transitionDidChange?(false)
        }
        transitionDidChange = nil
        PiPKitLog.d("PiP AVKit: pipeline video rilasciata, chiusura completata")
        completions.forEach { $0() }
    }
}
