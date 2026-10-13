//
//  PiPKitLog.swift
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

/// MRPiPKit's lifecycle messages. The host app routes them to its own log; by default they are discarded.
@MainActor
public enum PiPKitLog {
    public static var handler: (String) -> Void = { _ in }

    static func d(_ message: String) {
        handler(message)
    }

    /// Logs an AVKit or renderer error with its failure reason and underlying error, when present.
    static func failure(_ error: Error) {
        let error = error as NSError
        d("PiP AVKit: errore \(error.domain), codice \(error.code): \(error.localizedDescription)")
        if let reason = error.localizedFailureReason {
            d("PiP AVKit: motivo: \(reason)")
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            d("PiP AVKit: errore sottostante \(underlying.domain), codice \(underlying.code): \(underlying.localizedDescription)")
            if let reason = underlying.localizedFailureReason {
                d("PiP AVKit: motivo sottostante: \(reason)")
            }
        }
    }
}
