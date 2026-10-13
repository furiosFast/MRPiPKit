//
//  PiPErrors.swift
//  MRPiPKit
//
//  Created by Marco Ricca on 13/10/2026
//
//  Created for MRPiPKit in 13/10/2026
//  Using Swift 6.4
//
//  Copyright © 2026 Fast-Devs Project by Marco Ricca. All rights reserved.
//

import Foundation

/// A start the slot or the controller cannot honour, because a previous session is still in progress: the caller
/// receives it through `didFail` and closes its session, so it never stays active without a window.
public struct PiPStartRejectedError: LocalizedError {
    public var errorDescription: String? {
        "A previous Picture in Picture session is still in progress"
    }
}

extension NSError {
    /// Reported when AVKit gives up on a start without a renderer error of its own.
    static var pipContentUnavailable: NSError {
        NSError(domain: "MRPiPKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Picture in Picture content is not available"])
    }

    /// Reported when no window can host the AVKit source, so the start cannot even be requested.
    static var pipNoWindow: NSError {
        NSError(domain: "MRPiPKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "No window can host the Picture in Picture source"])
    }
}
