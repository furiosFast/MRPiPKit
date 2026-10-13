//
//  PiPHostingViewController+Rendering.swift
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
import QuartzCore
import SwiftUI

/// Rendering: animation snapshots in the foreground, direct model renders otherwise, and the sample buffers sent to AVKit.
extension PiPHostingViewController {
    /// Background rendering draws the model directly: the window's backing layers can be frozen there.
    var isAppInBackground: Bool {
        UIApplication.shared.applicationState == .background
    }

    var displayScale: CGFloat {
        max(1, traitCollection.displayScale)
    }

    func startForegroundRendering() {
        guard phase.isLive, !isAppInBackground else { return }
        guard let fps = animationFramesPerSecond, !UIAccessibility.isReduceMotionEnabled else {
            stopForegroundRendering()
            return
        }
        animationDeadline = CACurrentMediaTime() + PiPTimings.animationWindow
        animationLink.start(framesPerSecond: fps) { [weak self] link in
            guard let self else { link.invalidate(); return }
            renderForegroundFrame(link)
        }
    }

    func stopForegroundRendering() {
        animationLink.stop()
    }

    func renderForegroundFrame(_ link: CADisplayLink) {
        // Layer snapshots preserve SwiftUI animations but cannot supply fresh background content.
        guard phase.isLive, !isAppInBackground else {
            stopForegroundRendering()
            return
        }
        guard !UIAccessibility.isReduceMotionEnabled, phase.hasRequestedStart || animatesContinuously || link.timestamp < animationDeadline else {
            stopForegroundRendering()
            // Finish on the current model even if the last display-link tick preceded animation completion.
            renderPictureInPicture()
            return
        }
        let size = view.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        enqueue(bitmapRenderer.snapshot(of: view.layer, size: size, scale: displayScale))
    }

    /// Draw the current model rather than snapshotting a hosting layer that can be frozen in background.
    /// The caller owns the cadence; this does not start another rendering timer.
    func renderPictureInPicture() {
        guard phase.isLive else { return }
        let size = preferredContentSize
        guard size.width > 0, size.height > 0 else { return }
        let scale = displayScale
        let content = rootView
            .frame(width: size.width, height: size.height)
            .background(Color(uiColor: view.backgroundColor ?? .black))
            .environment(\.colorScheme, traitCollection.userInterfaceStyle == .dark ? .dark : .light)
            .environment(\.displayScale, scale)
            .transaction {
                $0.animation = nil
                $0.disablesAnimations = true
            }
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.render(rasterizationScale: scale) { [weak self] renderedSize, draw in
            guard renderedSize.width > 0, renderedSize.height > 0 else { return }
            guard let self else { return }
            enqueue(bitmapRenderer.image(size: renderedSize, scale: scale, drawingFlipped: draw))
        }
    }

    func updateSourceLayout(size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        guard sourceView.frame != bounds || displayLayer.frame != bounds else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sourceView.frame = bounds
        displayLayer.frame = bounds
        CATransaction.commit()
    }

    func enqueue(_ image: UIImage) {
        let duration = CMTime(value: 1, timescale: CMTimeScale(max(1, animationFramesPerSecond ?? 1)))
        guard phase.isLive, let sampleBufferRendering else { return }
        guard let buffer = PiPSampleBuffer.make(from: image, duration: duration, displaysImmediately: sampleBufferRendering.displaysImmediately) else {
            PiPKitLog.d("PiP AVKit: impossibile preparare il fotogramma dell'interfaccia")
            return
        }
        updateSourceLayout(size: image.size)
        guard sampleBufferRendering.enqueue(buffer) else { return }
        if !hasEnqueuedImage {
            hasEnqueuedImage = true
            PiPKitLog.d("PiP AVKit: primo fotogramma dell'interfaccia inviato")
        }
        startIfPossible()
    }
}
