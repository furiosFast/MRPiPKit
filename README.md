# MRPiPKit

[![SPM ready](https://img.shields.io/badge/SPM-ready-orange.svg)](https://swift.org/package-manager/)
![Platform](https://img.shields.io/badge/platforms-iOS%2018.0-F28D00.svg)
[![Swift](https://img.shields.io/badge/Swift-6.4-orange.svg)](https://swift.org)
[![Xcode](https://img.shields.io/badge/Xcode-27.1-blue.svg)](https://developer.apple.com/xcode)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Twitter](https://img.shields.io/badge/twitter-@FastDevsProject-blue.svg?style=flat)](https://twitter.com/FastDevsProject)

Picture in Picture for live SwiftUI content, built directly on AVKit. Any SwiftUI view becomes a PiP window: the kit renders it into a sample buffer, so dashboards, gauges and charts can float over other apps without a video player.

It handles the parts of the AVKit lifecycle that are easy to get wrong: a stop during the start transition, callbacks that never arrive, the iOS 27 sample buffer receiver and its asynchronous teardown, and stops requested while the app is in background.

## Features

- **No subclassing.** `PiPHostingViewController(rootView:)` wraps any SwiftUI view.
- **One lifecycle state.** A private phase enum tracks the AVKit session, so impossible combinations, such as a start confirmed while the receiver is being released, cannot be represented.
- **Bounded waits.** Startup timeouts, three stop renewals, a forced release and a bounded receiver flush: a silent AVKit never leaves your PiP controls locked.
- **Immediate release in background.** AVKit does not answer `stopPictureInPicture()` while the app is in background, with the screen locked or another app in front, so such a stop releases the session at once, which closes the window.
- **A stop during the start transition** waits for AVKit to confirm, then closes the window, instead of leaving a window nobody owns.
- **Controller reuse.** `PiPControllerSlot` runs the start sequence, forwards exits, keeps the idle controller after a confirmed stop for the next start, clears that session's callbacks, gives it the new activation's content, rejects a start while one is still active, and drops the idle controller on a memory warning.
- **Balanced transitions.** `transitionDidChange` reports `true` from the start request and while closing, and `false` once the window is up or the session has settled after a stop or a failure: controls locked with it never stay locked.
- **Multi-window aware.** The source goes into a window of the foreground-active scene, where AVKit can start; without any window the start fails at once instead of timing out.
- **Foreground animation.** After each update the window captures the SwiftUI animation for one second, at six frames per second by default, also while a table in the app is scrolling. Reduce Motion disables it.
- **Zero third-party dependencies**: AVKit, SwiftUI, UIKit and Combine only.

## Requirements

- iOS 18.0+ or Mac Catalyst at run time; the iOS 27 receiver path is used where available
- Xcode 27.1+ with Swift 6.4 to build: the iOS 27 SDK is needed even when deploying to iOS 18, and the manifest's tools version rejects older toolchains

The app must declare the `audio` background mode, and activate an audio session with the `.playback` category before starting a PiP.

## Installation

### Swift Package Manager

Add the package to the `dependencies` array of your `Package.swift`:

```swift
dependencies: [
    .package(path: "../MRPiPKit"),
]
```

Then add `MRPiPKit` to your target dependencies. In Xcode, use **File ▸ Add Package Dependencies… ▸ Add Local…** and pick the package folder.

## Usage

```swift
import AVFoundation
import Combine
import MRPiPKit
import SwiftUI

@MainActor
final class GaugePiP {
    /// `animationFramesPerSecond: nil` renders only explicit updates.
    private let slot = PiPControllerSlot<GaugeView>()
    private let model = GaugeModel()

    /// The PiP closed from outside the app, or AVKit gave up on the start: end your session.
    var exits: AnyPublisher<Void, Never> {
        slot.exitPublisher
    }

    func start() throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try AVAudioSession.sharedInstance().setActive(true)
        guard let controller = slot.activate(
            interfaceStyle: .dark,
            size: CGSize(width: 370, height: 30),
            transitionDidChange: { isTransitioning in /* true while starting or closing: lock your PiP switches */ },
            didFail: { error in /* explain why the window did not appear */ },
            makeContent: { GaugeView(model: model) }
        ) else { return }
        controller.restoreInterface = { /* show the screen the PiP came from */ true }
        controller.startPictureInPicture()
    }

    func update(value: Double) {
        model.value = value
        slot.active?.scheduleRendering()
    }

    func resize(to size: CGSize) {
        slot.active?.applyLayout(size: size)
        slot.active?.scheduleRendering()
    }

    func stop(completion: @escaping () -> Void) {
        // The completion runs once AVKit has closed the window and released the video pipeline.
        slot.deactivate(completion: completion)
    }
}
```

The kit drives one PiP per slot. Which PiP is active, the handoff between them and the audio session belong to your app.

`didFail` receives `PiPStartRejectedError` when a slot still has an active controller: close your session in that case, because no window will report its end. Any other error means AVKit did not show the window; an exit follows.

### Private API

The controller sets the private `controlsStyle` key, which hides the playback controls that mean nothing for live content. The key is set only when the class still answers to it, so a future system without it keeps the controls instead of crashing.

### Logging

The kit is silent by default. Route its lifecycle messages to your own log once, before the first PiP starts:

```swift
PiPKitLog.handler = { message in print(message) }
```

## Structure

| Folder | Contents |
|---|---|
| `Host` | `PiPHostingViewController` with its public interface and the AVKit callbacks; its lifecycle in `+Startup`, `+Stopping` and `+Rendering`; the session phases and the time limits |
| `Rendering` | The two sample buffer paths, before and from iOS 27, the JPEG sample buffer factory, the bitmap renderer and the animation display link |
| `Slot` | `PiPControllerSlot` |
| `Support` | Logging, errors, the key window and the bounded wait |

AVKit's delegate methods stay in the controller's class body: Objective-C members cannot live in extensions of a generic class.

## License

MRPiPKit is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
