//
//  AwaitWithTimeout.swift
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

/// Receives the result of the race between an operation and its time limit: only the first to arrive resumes the wait.
private actor TimeoutRace {
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func finish(inTime: Bool) {
        continuation?.resume(returning: inTime)
        continuation = nil
    }
}

/// Waits for `operation` at most `seconds` and tells whether it finished in time. A system call that never answers,
/// such as a receiver flush, must not leave the PiP in transition forever: the operation is not interrupted and ends
/// on its own, while the caller moves on.
func awaitWithTimeout(_ seconds: TimeInterval, _ operation: @escaping @Sendable () async -> Void) async -> Bool {
    await withCheckedContinuation { continuation in
        let race = TimeoutRace(continuation)
        let deadline = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await race.finish(inTime: false)
        }
        Task {
            await operation()
            deadline.cancel()
            await race.finish(inTime: true)
        }
    }
}
