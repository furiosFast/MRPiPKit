//
//  PiPHostingViewController+Startup.swift
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

/// Starting a session: the source, the readiness signals AVKit needs, the deferred request and its timeouts.
extension PiPHostingViewController {
    /// Puts the AVKit source in the window behind the app's content, with a new image pipeline, and points the controller
    /// at it: the one reused after a confirmed stop, or a new one. `nil` when the app has no window to host the source.
    func attachSource() -> AVPictureInPictureController? {
        guard let window = view.window ?? UIApplication.shared.pipKeyWindow else { return nil }
        // AVKit needs a laid-out source in the window. Keep it behind the app's content,
        // rather than making its layer invisible while the first image is being prepared.
        view.layoutIfNeeded()
        sourceView.isUserInteractionEnabled = false
        sourceView.accessibilityElementsHidden = true
        sourceView.isHidden = false
        window.insertSubview(sourceView, at: 0)
        sourceView.layer.addSublayer(displayLayer)
        updateSourceLayout(size: view.bounds.size)
        displayLayer.videoGravity = .resizeAspect
        sampleBufferRendering = makePiPSampleBufferRendering(for: displayLayer)
        let contentSource = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
        let controller: AVPictureInPictureController
        if let existingController = self.controller {
            controller = existingController
            controller.contentSource = contentSource
            PiPKitLog.d("PiP AVKit: riutilizzo del controller dopo la chiusura confermata")
        } else {
            controller = AVPictureInPictureController(contentSource: contentSource)
            self.controller = controller
        }
        controller.delegate = self
        controller.requiresLinearPlayback = true
        // Private key that hides the playback controls, meaningless for live content. Setting a key the class no longer has
        // raises an Objective-C exception, so a system without it simply keeps the controls.
        if controller.responds(to: NSSelectorFromString("setControlsStyle:")) {
            controller.setValue(1, forKey: "controlsStyle")
        }
        // Every start is explicit: backgrounding must not start an idle session.
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        return controller
    }

    /// AVKit starts only while PiP is possible: each change retries the pending start.
    func observePossibility(of controller: AVPictureInPictureController) {
        controller.publisher(for: \.isPictureInPicturePossible, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] possible in
                guard let self, phase.isLive else { return }
                PiPKitLog.d("PiP AVKit: possible=\(possible)")
                startIfPossible()
            }
            .store(in: &readinessObservers)
    }

    func observeReadiness() {
        let notifications = NotificationCenter.default
        notifications.publisher(for: UIApplication.willResignActiveNotification)
            .merge(with: notifications.publisher(for: UIScene.willDeactivateNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self, !phase.hasRequestedStart else { return }
                if let scene = notification.object as? UIScene, scene !== sourceView.window?.windowScene {
                    return
                }
                cancelStartupTimeout()
            }
            .store(in: &readinessObservers)
        notifications.publisher(for: UIScene.didActivateNotification)
            .merge(with: notifications.publisher(for: UIApplication.didBecomeActiveNotification))
            .merge(with: notifications.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, phase.isLive else { return }
                scheduleRendering(continuously: animatesContinuously)
                startIfPossible()
            }
            .store(in: &readinessObservers)
        notifications.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, phase.isLive else { return }
                // In background only the owner's explicit updates render, at its own cadence.
                stopForegroundRendering()
                renderPictureInPicture()
            }
            .store(in: &readinessObservers)
        notifications.publisher(for: .AVSampleBufferDisplayLayerReadyForDisplayDidChange, object: displayLayer)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.startIfPossible() }
            .store(in: &readinessObservers)
    }

    func startIfPossible() {
        guard case .preparing = phase, let controller, !controller.isPictureInPictureActive else { return }
        moveSourceToActiveSceneIfNeeded()
        guard isSourceForegroundActive else {
            cancelStartupTimeout()
            return
        }
        scheduleStartupTimeout()
        guard isReadyToRequestStart(controller) else { return }
        guard phase == .preparing(pendingRequest: nil) else { return }
        let id = UUID()
        phase = .preparing(pendingRequest: id)
        // Leave the rendering/KVO callback before asking AVKit to present another window after a handoff.
        DispatchQueue.main.async { [weak self] in
            guard let self, phase == .preparing(pendingRequest: id) else { return }
            phase = .preparing(pendingRequest: nil)
            guard let controller = self.controller, !controller.isPictureInPictureActive else { return }
            guard isSourceForegroundActive else {
                cancelStartupTimeout()
                return
            }
            guard isReadyToRequestStart(controller) else { return }
            phase = .requested
            // AVKit gets a full timeout after the actual request, independently of first-image preparation.
            cancelStartupTimeout()
            scheduleStartupTimeout()
            PiPKitLog.d("PiP AVKit: richiesta di avvio")
            controller.startPictureInPicture()
        }
    }

    /// Before the start is requested, a source left in a scene that is not active moves to the window of the active scene.
    /// Activated while the whole app was in background, the controller went to a background scene's window; on iPad the
    /// user can come back through another window, and the start would wait for a scene that may never come back.
    func moveSourceToActiveSceneIfNeeded() {
        guard !isSourceForegroundActive, let window = UIApplication.shared.pipKeyWindow, window !== sourceView.window,
              window.windowScene?.activationState == .foregroundActive else { return }
        PiPKitLog.d("PiP AVKit: sorgente spostata nella finestra della scena attiva prima della richiesta di avvio")
        window.addSubview(view)
        window.insertSubview(sourceView, at: 0)
    }

    /// AVKit accepts a start only with a first image ready for display and PiP possible right now.
    func isReadyToRequestStart(_ controller: AVPictureInPictureController) -> Bool {
        hasEnqueuedImage && displayLayer.isReadyForDisplay && controller.isPictureInPicturePossible
    }

    var isSourceForegroundActive: Bool {
        sourceView.window?.windowScene?.activationState == .foregroundActive && UIApplication.shared.applicationState == .active
    }

    /// Armed only while the source scene is active: a system sheet shown by the owner can keep the app inactive for as
    /// long as it is on screen.
    func scheduleStartupTimeout() {
        guard startupTask == nil else { return }
        startupTask = Task { [weak self] in
            do { try await Task.sleep(for: PiPTimings.startupTimeout) } catch { return }
            guard !Task.isCancelled, let self else { return }
            // Cleared before any other check: a stale reference would block every later timeout.
            startupTask = nil
            guard phase.isLive || phase == .cancellingStart, let controller else { return }
            if controller.isPictureInPictureActive {
                // The window is up but DidStart never came: settle the start instead of staying in transition.
                confirmStart(of: controller, message: "PiP AVKit: finestra attiva senza conferma di avvio, sessione considerata avviata")
                return
            }
            switch phase {
                case .cancellingStart:
                    // The abandoned start waited one more timeout and AVKit never confirmed: release the source now.
                    PiPKitLog.d("PiP AVKit: nessuna conferma dopo l'annullamento dell'avvio, rilascio della sorgente")
                    releaseRendering()
                    return
                case .starting:
                    // WillStart arrived but DidStart did not. AVKit is still presenting, so its source stays attached:
                    // report the failure now, then wait one more timeout for DidStart or a start failure.
                    let error = startupError
                    PiPKitLog.d("PiP AVKit: timeout dopo l'inizio della transizione di avvio, attesa di una conferma prima del rilascio")
                    PiPKitLog.failure(error)
                    cancelStartInTransition()
                    reportStartFailure(error)
                    return
                default:
                    break
            }
            guard phase.hasRequestedStart || isSourceForegroundActive else { return }
            PiPKitLog.d("PiP AVKit: timeout, provider=\(type(of: self)), firstImage=\(hasEnqueuedImage), readyForDisplay=\(displayLayer.isReadyForDisplay), sourceScene=\(sourceView.window?.windowScene?.activationState.rawValue ?? -1), appState=\(UIApplication.shared.applicationState.rawValue), possible=\(controller.isPictureInPicturePossible), phase=\(phase), retry=\(hasRetriedStartup)")
            if recoverSilentStartup() {
                return
            }
            let error = startupError
            PiPKitLog.failure(error)
            markExplicitStop()
            releaseRendering()
            reportStartFailure(error)
        }
    }

    func cancelStartupTimeout() {
        startupTask?.cancel()
        startupTask = nil
    }

    /// Abandons a start AVKit is already presenting: rendering stops, while the controller keeps itself, its delegate and
    /// its source. DidStart then closes the window at once; a start failure or one more startup timeout releases it.
    func cancelStartInTransition() {
        markExplicitStop()
        phase = .cancellingStart
        readinessObservers.removeAll()
        stopForegroundRendering()
        scheduleStartupTimeout()
    }

    /// A request with no WillStart and no renderer error can be ignored by AVKit during a handoff. Retry once,
    /// after retiring that inactive controller and its receiver; the owner's session continues meanwhile.
    func recoverSilentStartup() -> Bool {
        guard phase == .requested, !hasRetriedStartup, isSourceForegroundActive,
              sampleBufferRendering?.error == nil, controller?.isPictureInPictureActive == false else { return false }
        let id = UUID()
        startupRecoveryID = id
        let transition = transitionDidChange
        let continuously = animatesContinuously
        canReuseController = false
        stopCompletions.append { [weak self] in
            guard let self, startupRecoveryID == id, !explicitStop else { return }
            transitionDidChange = transition
            startPictureInPicture()
            hasRetriedStartup = true
            scheduleRendering(continuously: continuously)
        }
        PiPKitLog.d("PiP AVKit: richiesta senza transizione, un solo tentativo di recupero dopo il rilascio della pipeline")
        releaseRendering()
        return true
    }

    /// DidStart, or an active window the startup timeout found without that callback: the session leaves the transition.
    func confirmStart(of pictureInPictureController: AVPictureInPictureController, message: String) {
        cancelStartupTimeout()
        // The session reached the window: after a confirmed stop the controller can be reused.
        canReuseController = true
        guard !explicitStop, phase.isLive else {
            // AVKit may confirm a start after cancellation; immediately stop that same session.
            PiPKitLog.d("PiP AVKit: avvio confermato dopo l'arresto, chiusura immediata della finestra")
            if phase.isLive || phase == .cancellingStart {
                phase = .active
                beginStopping()
            }
            // The app may already be in background, where the observer of `beginStopping()` would never fire.
            requestWindowClose(pictureInPictureController)
            return
        }
        phase = .active
        PiPKitLog.d(message)
        transitionDidChange?(false)
    }

    /// The renderer's own error, or a generic one when AVKit gave up without any.
    var startupError: Error {
        sampleBufferRendering?.error ?? NSError.pipContentUnavailable
    }

    /// Tells the slot's owner that the window did not appear, then ends the session.
    func reportStartFailure(_ error: Error) {
        didFail?(error)
        exitSubject.send()
    }
}
