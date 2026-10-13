//
//  PiPBitmapRenderer.swift
//  MRPiPKit
//
//  Created by Marco Ricca on 13/10/2026
//
//  Created for MRPiPKit in 13/10/2026
//  Using Swift 6.4
//
//  Copyright © 2026 Fast-Devs Project by Marco Ricca. All rights reserved.
//

import UIKit

/// Draws the PiP snapshots into opaque bitmaps, reusing one renderer until the dimensions or the display scale change.
@MainActor
final class PiPBitmapRenderer {
    private var cached: (renderer: UIGraphicsImageRenderer, scale: CGFloat)?

    /// A layer as it is on screen now, including the intermediate frames of a running SwiftUI animation.
    func snapshot(of layer: CALayer, size: CGSize, scale: CGFloat) -> UIImage {
        renderer(size: size, scale: scale).image { context in
            layer.render(in: context.cgContext)
        }
    }

    /// An image that `draw` paints in Core Graphics coordinates, like an `ImageRenderer` output: UIKit's bitmap context
    /// flips the Y axis, so the drawing is flipped back.
    func image(size: CGSize, scale: CGFloat, drawingFlipped draw: (CGContext) -> Void) -> UIImage {
        renderer(size: size, scale: scale).image { context in
            let cgContext = context.cgContext
            cgContext.saveGState()
            cgContext.translateBy(x: 0, y: size.height)
            cgContext.scaleBy(x: 1, y: -1)
            draw(cgContext)
            cgContext.restoreGState()
        }
    }

    /// Drops the cached renderer together with the session's images.
    func reset() {
        cached = nil
    }

    private func renderer(size: CGSize, scale: CGFloat) -> UIGraphicsImageRenderer {
        let bounds = CGRect(origin: .zero, size: size)
        if let cached, cached.renderer.format.bounds == bounds, cached.scale == scale {
            return cached.renderer
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        cached = (renderer, scale)
        return renderer
    }
}
