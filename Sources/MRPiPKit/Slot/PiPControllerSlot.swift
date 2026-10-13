//
//  PiPControllerSlot.swift
//  MRPiPKit
//
//  Created by Marco Ricca on 09/10/2026
//
//  Created for MRPiPKit in 13/10/2026
//  Using Swift 6.4
//
//  Copyright © 2026 Fast-Devs Project by Marco Ricca. All rights reserved.
//

import Combine
import SwiftUI
import UIKit

/// The hosting controller a PiP is showing, plus the idle one retained after a confirmed stop for the next start:
/// one start, stop and reuse sequence for every PiP of an app.
@MainActor
public final class PiPControllerSlot<Content: View> {
    public private(set) var active: PiPHostingViewController<Content>?
    /// Exits of the active controller: the PiP closed from outside the app, or a start AVKit gave up on.
    public var exitPublisher: AnyPublisher<Void, Never> {
        exitSubject.eraseToAnyPublisher()
    }

    private let animationFramesPerSecond: Int?
    private let backgroundColor: UIColor
    private var idle: PiPHostingViewController<Content>?
    /// The controller `deactivate` is stopping, until its teardown completes.
    private var closing: PiPHostingViewController<Content>?
    private let exitSubject = PassthroughSubject<Void, Never>()
    private var exitObservation: AnyCancellable?
    private var memoryWarningObservation: AnyCancellable?

    /// - Parameters:
    ///   - animationFramesPerSecond: Frame rate of the animation captured in the foreground for one second after each
    ///     update, six by default. `nil`, zero or a negative value renders only explicit updates, for content that must
    ///     not animate, such as a screen-capture readout that would count its own redraws.
    ///   - backgroundColor: Opaque color behind the content, black by default; the images carry no transparency.
    public init(animationFramesPerSecond: Int? = 6, backgroundColor: UIColor = .black) {
        self.animationFramesPerSecond = animationFramesPerSecond
        self.backgroundColor = backgroundColor
        // An idle controller only saves the next start some work: under memory pressure it is the first thing to go.
        // The active one is untouched, and the next start simply makes a new controller.
        memoryWarningObservation = NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, idle != nil else { return }
                idle = nil
                PiPKitLog.d("PiP: controller inattivo rilasciato per memoria insufficiente")
            }
    }

    /// Reuses the idle controller of the previous confirmed stop, with `makeContent()` as its new root, or makes one around
    /// it; configures it for this session, anchors it off screen at `size` and makes it the active one; its exits reach
    /// `exitPublisher` until `deactivate`. While a controller is still active, or the previous one is still closing, the
    /// start is rejected through `didFail` with `PiPStartRejectedError`, which the caller answers by closing its session:
    /// start the next session from the completion of `deactivate`.
    public func activate(interfaceStyle: UIUserInterfaceStyle, size: CGSize, transitionDidChange: @escaping (Bool) -> Void, didFail: @escaping (Error) -> Void, makeContent: () -> Content) -> PiPHostingViewController<Content>? {
        // One controller at a time: a new session never overlaps the teardown of the previous one, so `closing` always
        // names the only pending stop that a later `deactivate` waits for.
        guard active == nil, closing == nil else {
            PiPKitLog.d(active != nil ? "PiP: avvio rifiutato, un controller è ancora attivo" : "PiP: avvio rifiutato, il controller precedente sta ancora chiudendo")
            didFail(PiPStartRejectedError())
            return nil
        }
        let content = makeContent()
        let controller: PiPHostingViewController<Content>
        if let idle {
            // The AVKit controller is reused, the content never: it always comes from this activation.
            idle.rootView = content
            controller = idle
        } else {
            controller = PiPHostingViewController(rootView: content, animationFramesPerSecond: animationFramesPerSecond, backgroundColor: backgroundColor)
        }
        idle = nil
        controller.configureView(interfaceStyle: interfaceStyle)
        controller.transitionDidChange = transitionDidChange
        controller.didFail = didFail
        controller.anchorOffscreen(size: size)
        exitObservation = controller.exitPublisher.sink { [weak self] in self?.exitSubject.send() }
        active = controller
        return controller
    }

    /// Stops the active controller and detaches its view; keeps it idle only when AVKit confirmed the stop. The completion
    /// runs once the window is closed and the video pipeline released, also when a stop is already in progress.
    public func deactivate(completion: @escaping () -> Void) {
        guard let controller = active else {
            // A stop still in progress: this completion waits for the same teardown instead of running early.
            if let closing {
                closing.stopPictureInPicture(completion: completion)
            } else {
                completion()
            }
            return
        }
        closing = controller
        controller.stopPictureInPicture { [weak self, weak controller] in
            if let self, closing === controller {
                closing = nil
            }
            if let controller, controller.canRestartPictureInPicture {
                // An idle controller keeps nothing of the session that ended: the next activation sets its own callbacks.
                controller.didFail = nil
                controller.restoreInterface = nil
                self?.idle = controller
            }
            completion()
        }
        active = nil
        exitObservation = nil
        controller.view.removeFromSuperview()
    }

    /// An owner that goes away must not leave its PiP window and hidden view behind. The controller retains itself while
    /// closing, so the teardown completes after the slot is gone.
    isolated deinit {
        active?.stopPictureInPicture(completion: nil)
        active?.view.removeFromSuperview()
    }
}
