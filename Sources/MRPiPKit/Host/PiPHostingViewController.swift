//
//  PiPHostingViewController.swift
//  MRPiPKit
//
//  Created by Marco Ricca on 09/10/2026
//
//  Created for MRPiPKit in 13/10/2026
//  Using Swift 6.4
//
//  Copyright © 2026 Fast-Devs Project by Marco Ricca. All rights reserved.
//

import AVKit
import Combine
import SwiftUI

/// Shows a SwiftUI view as a Picture in Picture window, rendered into image sample buffers for AVKit, so it floats over
/// other apps without a video player. After each foreground update the window also captures the SwiftUI animation;
/// background updates render the current model directly, independently of the window's backing layers.
///
/// The lifecycle is split by responsibility into `+Startup`, `+Stopping` and `+Rendering`.
@MainActor
public final class PiPHostingViewController<Content: View>: UIHostingController<Content>, @MainActor AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    /// Frame rate of the foreground animation snapshots taken after each update. `nil` renders only explicit updates,
    /// for content that must not animate, such as a screen-capture readout that would count its own redraws.
    public let animationFramesPerSecond: Int?

    /// - Parameters:
    ///   - rootView: The SwiftUI content of the PiP window.
    ///   - animationFramesPerSecond: Six by default; see ``animationFramesPerSecond``.
    public init(rootView: Content, animationFramesPerSecond: Int? = 6) {
        self.animationFramesPerSecond = animationFramesPerSecond
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    @MainActor public dynamic required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not available")
    }

    /// Called when the user returns to the app from the PiP window: restore the interface the PiP belongs to and answer
    /// whether it is shown. Without it, the current interface stays.
    public var restoreInterface: (() -> Bool)?

    // MARK: - Slot interface

    /// A stopped controller is reusable only after DidStop and complete video teardown.
    var canRestartPictureInPicture: Bool {
        phase == .idle && canReuseController && controller != nil
    }

    var exitPublisher: AnyPublisher<Void, Never> {
        exitSubject.eraseToAnyPublisher()
    }

    var didFail: ((Error) -> Void)?

    /// `true` from the start request and while closing, `false` once the window is up or the session has settled.
    var transitionDidChange: ((Bool) -> Void)?

    // MARK: - Session state

    // Internal rather than private only so the lifecycle extensions in the sibling files can reach it; nothing outside
    // this controller touches it.
    let exitSubject = PassthroughSubject<Void, Never>()
    var displayLayer = AVSampleBufferDisplayLayer()
    let sourceView = UIView()
    var controller: AVPictureInPictureController?
    var sampleBufferRendering: (any PiPSampleBufferRendering)?
    var readinessObservers = Set<AnyCancellable>()
    let animationLink = PiPDisplayLink()
    let bitmapRenderer = PiPBitmapRenderer()
    var animationDeadline: CFTimeInterval = 0
    var animatesContinuously = false
    var phase = PiPSessionPhase.idle {
        didSet { closingRetention = phase.isClosing ? self : nil }
    }

    /// The owner asked for the stop, as opposed to the user closing the window, the system or a failure.
    var explicitStop = false
    var hasEnqueuedImage = false
    /// Set when the session reaches `.active`; a failed or cancelled start, a missing stop callback, a silent-start
    /// recovery or a teardown timeout leave it false, so that controller is discarded.
    var canReuseController = false
    var hasRetriedStartup = false
    var startupRecoveryID: UUID?
    var startupTask: Task<Void, Never>?
    var stopTimeoutTask: Task<Void, Never>?
    /// Releases a stop still waiting for AVKit as soon as the app moves to the background, where AVKit never answers.
    var backgroundStopObservation: AnyCancellable?
    var stopCompletions: [() -> Void] = []
    /// While closing, the controller retains itself: its owner may detach at once, and the teardown still completes.
    private var closingRetention: PiPHostingViewController?
    private var isRenderScheduled = false

    // MARK: - Configuration

    func configureView(interfaceStyle: UIUserInterfaceStyle) {
        overrideUserInterfaceStyle = interfaceStyle
        view.backgroundColor = .black
        additionalSafeAreaInsets = .zero
        view.insetsLayoutMarginsFromSafeArea = false
        view.preservesSuperviewLayoutMargins = false
        view.layoutMargins = .zero
        safeAreaRegions = []
        view.invalidateIntrinsicContentSize()
    }

    func anchorOffscreen(size: CGSize) {
        applyLayout(size: size)
        UIApplication.shared.pipKeyWindow?.addSubview(view)
        view.layoutIfNeeded()
    }

    /// The hosting view lives just left of the screen: laid out and in a window, as AVKit and SwiftUI need, but never seen.
    private static var offscreenGap: CGFloat {
        10
    }

    /// Resizes the PiP content, for example after switching to an extended layout; call `scheduleRendering()` next.
    public func applyLayout(size: CGSize) {
        guard preferredContentSize != size else { return }
        view.frame = CGRect(origin: CGPoint(x: -(size.width + Self.offscreenGap), y: 0), size: size)
        preferredContentSize = size
    }

    /// Redraws the window after the content changed. Requests in the same main-queue turn are coalesced; in background
    /// the model is rendered at once. `continuously` keeps the foreground animation frames flowing until the next update.
    public func scheduleRendering(continuously: Bool = false) {
        guard phase.isLive else { return }
        animatesContinuously = continuously
        if isAppInBackground {
            renderPictureInPicture()
            return
        }
        guard !isRenderScheduled else { return }
        isRenderScheduled = true
        view.setNeedsLayout()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isRenderScheduled = false
            guard phase.isLive else { return }
            view.layoutIfNeeded()
            startForegroundRendering()
            // Animated content sends the hosting view's intermediate frames. Sending the final model first
            // would make the next animation frame jump backwards; direct rendering remains the fallback.
            if !animationLink.isRunning {
                renderPictureInPicture()
            }
        }
    }

    // MARK: - Session

    /// Starts the PiP window for the content. The start is asynchronous: `transitionDidChange` reports when it settles,
    /// and `didFail` when AVKit did not show the window.
    public func startPictureInPicture() {
        guard phase == .idle, controller == nil || canReuseController else {
            // The slot never reaches this. A caller that does gets a rejected start, which it answers by closing its
            // session instead of staying active without a window.
            PiPKitLog.d("PiP AVKit: avvio rifiutato, sessione precedente ancora in corso (phase=\(phase))")
            didFail?(PiPStartRejectedError())
            return
        }
        phase = .preparing(pendingRequest: nil)
        explicitStop = false
        startupRecoveryID = nil
        hasRetriedStartup = false
        canReuseController = false
        hasEnqueuedImage = false
        transitionDidChange?(true)
        guard let controller = attachSource() else {
            // Without a window the source cannot be attached: report the failure at once instead of after a timeout.
            PiPKitLog.d("PiP AVKit: nessuna finestra per la sorgente, avvio non possibile")
            phase = .idle
            reportStartFailure(NSError.pipContentUnavailable)
            return
        }
        observeReadiness()
        observePossibility(of: controller)
        renderPictureInPicture()
        startForegroundRendering()
        startIfPossible()
    }

    func stopPictureInPicture(completion: (() -> Void)?) {
        if let completion {
            stopCompletions.append(completion)
        }
        // An explicit stop cancels an automatic start recovery too.
        markExplicitStop()
        switch phase {
            case .cancellingStart, .stopping, .tearingDown:
                // The completion runs when the current teardown finishes.
                return
            case .starting where controller?.isPictureInPictureActive != true:
                // WillStart arrived: AVKit is already presenting the window, and detaching its source now could leave a
                // window nobody closes.
                PiPKitLog.d("PiP AVKit: arresto durante la transizione di avvio, attesa della conferma per chiudere la finestra")
                cancelStartInTransition()
            default:
                guard let controller, controller.isPictureInPictureActive else {
                    // stopPictureInPicture only stops an active PiP. Before WillStart, detach the unconfirmed start instead.
                    if phase.hasRequestedStart {
                        PiPKitLog.d("PiP AVKit: avvio non confermato annullato, rimozione della sorgente")
                    }
                    releaseRendering()
                    return
                }
                beginStopping()
                controller.canStartPictureInPictureAutomaticallyFromInline = false
                // A visible PiP keeps its source and last image until AVKit completes the closing animation.
                controller.stopPictureInPicture()
                if isAppInBackground {
                    PiPKitLog.d("PiP AVKit: arresto con l'app in background, rilascio senza attendere AVKit")
                    releaseWithoutStopConfirmation()
                }
        }
    }

    // MARK: - AVKit callbacks

    // Objective-C members cannot live in extensions of a generic class: the delegate methods stay in the class body.

    public func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard controller === pictureInPictureController, phase == .requested else { return }
        phase = .starting
        PiPKitLog.d("PiP AVKit: transizione di avvio iniziata")
    }

    public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard controller === pictureInPictureController else { return }
        confirmStart(of: pictureInPictureController, message: "PiP AVKit: avvio confermato")
    }

    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        guard controller === pictureInPictureController, phase != .tearingDown else { return }
        let wasExplicitStop = explicitStop
        canReuseController = false
        PiPKitLog.failure(error)
        releaseRendering()
        guard !wasExplicitStop else { return }
        reportStartFailure(error)
    }

    public func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard controller === pictureInPictureController else { return }
        beginStopping()
    }

    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard controller === pictureInPictureController, phase != .tearingDown else { return }
        PiPKitLog.d("PiP AVKit: chiusura della finestra confermata")
        finishStopping()
    }

    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        guard controller === pictureInPictureController else { completionHandler(false); return }
        if explicitStop || startupRecoveryID != nil {
            // The app already shows the intended interface during its own stop or a handoff to another PiP.
            // Acknowledge restoration so AVKit can finish, without reopening the previous detail.
            PiPKitLog.d("PiP AVKit: ripristino confermato sull'interfaccia corrente durante l'arresto esplicito")
            completionHandler(true)
            return
        }
        // Without a restore action the current interface stays.
        completionHandler(restoreInterface?() ?? true)
    }

    public nonisolated func pictureInPictureController(_: AVPictureInPictureController, setPlaying _: Bool) {}

    public nonisolated func pictureInPictureController(_: AVPictureInPictureController, didTransitionToRenderSize _: CMVideoDimensions) {}

    /// A start of negative infinity marks live content: no seekable range, no progress to show.
    public nonisolated func pictureInPictureControllerTimeRangeForPlayback(_: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    public nonisolated func pictureInPictureControllerIsPlaybackPaused(_: AVPictureInPictureController) -> Bool {
        false
    }

    public nonisolated func pictureInPictureController(_: AVPictureInPictureController, skipByInterval _: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    isolated deinit {
        startupTask?.cancel()
        stopTimeoutTask?.cancel()
        animationLink.stop()
        PiPKitLog.d("PiPHostingViewController<\(Content.self)> DEINITIALIZATED!!!!")
    }
}
