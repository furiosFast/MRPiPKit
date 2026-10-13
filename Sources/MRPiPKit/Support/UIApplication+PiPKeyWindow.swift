//
//  UIApplication+PiPKeyWindow.swift
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

extension UIApplication {
    /// The window that hosts the off-screen PiP view and its AVKit source. AVKit starts only from a foreground-active
    /// scene: the best scene with a usable window is chosen first, active, then inactive but in the foreground, then the
    /// rest, and only then its window. `connectedScenes` has no order, and on iPad with several windows a background scene
    /// keeps a key window of its own, where the start would wait until that scene comes back.
    var pipKeyWindow: UIWindow? {
        let scene = connectedScenes.compactMap { $0 as? UIWindowScene }.filter { $0.pipHostWindow != nil }.min { $0.pipStartRank < $1.pipStartRank }
        return scene?.pipHostWindow
    }
}

private extension UIWindowScene {
    /// The key window, or else the first visible window at the normal level: never a keyboard or text-effects window.
    var pipHostWindow: UIWindow? {
        keyWindow ?? windows.first { !$0.isHidden && $0.windowLevel == .normal }
    }

    var pipStartRank: Int {
        switch activationState {
            case .foregroundActive: 0
            case .foregroundInactive: 1
            default: 2
        }
    }
}
