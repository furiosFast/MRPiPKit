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
    private var idle: PiPHostingViewController<Content>?
    private let exitSubject = PassthroughSubject<Void, Never>()
    private var exitObservation: AnyCancellable?
    private var memoryWarningObservation: AnyCancellable?

    /// - Parameter animationFramesPerSecond: Given to every controller the slot makes; see
    ///   ``PiPHostingViewController/animationFramesPerSecond``.
    public init(animationFramesPerSecond: Int? = 6) {
        self.animationFramesPerSecond = animationFramesPerSecond
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
    /// it; configures it
    /// for this session, anchors it off screen at `size` and makes it the active one; its exits reach
    /// `exitPublisher` until `deactivate`. While a controller is still active the start is rejected through
    /// `didFail` with `PiPStartRejectedError`, which the caller answers by closing its session.
    public func activate(interfaceStyle: UIUserInterfaceStyle, size: CGSize, transitionDidChange: @escaping (Bool) -> Void, didFail: @escaping (Error) -> Void, makeContent: () -> Content) -> PiPHostingViewController<Content>? {
        guard active == nil else {
            PiPKitLog.d("PiP: avvio rifiutato, un controller è ancora attivo")
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
            controller = PiPHostingViewController(rootView: content, animationFramesPerSecond: animationFramesPerSecond)
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

    /// Stops the active controller and detaches its view; keeps it idle only when AVKit confirmed the stop.
    public func deactivate(completion: @escaping () -> Void) {
        guard let controller = active else {
            completion()
            return
        }
        controller.stopPictureInPicture { [weak self, weak controller] in
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
}
