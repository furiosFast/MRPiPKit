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

- **No subclassing.** `PiPControllerSlot` makes the hosting controller around any SwiftUI view you give `activate`; controllers are never created directly, because only the slot anchors, sizes and wires them.
- **One lifecycle state.** An internal phase enum tracks preparation, startup, playback, cancellation, stopping and teardown.
- **Bounded waits.** Startup timeouts, up to three stop renewals, forced release and a receiver teardown timeout handle missing AVKit callbacks. Before a start request is sent, preparation waits while the source scene or app is inactive; its timeout resumes when both are active.
- **Release in background.** A stop requested for an active PiP while the app is in background begins teardown without waiting for AVKit's stop callback. A stop already in progress does the same when the app enters background; receiver cleanup remains asynchronous.
- **A stop during the start transition** waits for AVKit to confirm, then closes the window, instead of leaving a window nobody owns.
- **Controller reuse.** `PiPControllerSlot` configures controllers and forwards exits. After a confirmed stop and successful teardown, it keeps the idle controller for the next activation, supplies fresh content and clears the previous session's callbacks. It rejects activation while a controller is active or closing, and drops the idle controller on a memory warning.
- **Completions you can wait on.** `deactivate(completion:)` waits for teardown, including when called again during a stop. If receiver cleanup exceeds its timeout, the pipeline is abandoned and the controller is discarded before the completions run.
- **Transition notifications.** `transitionDidChange` reports `true` from the start request and while closing, and `false` once the window is up or teardown settles. Treat it as a Boolean state: `true` may repeat, and the single automatic startup retry keeps the transition open.
- **Scene selection.** Window lookup prefers a foreground-active scene, then a foreground-inactive scene, then other scenes. Startup waits for the chosen scene and app to become active; if another scene of the app becomes active first, before the start request, the source moves to its window. Without a usable window it fails immediately. When several scenes share the same state, selection does not identify which one initiated the request.
- **No orphans.** A slot that goes away closes its PiP, and a controller whose window AVKit closed without callbacks is never reused.
- **Foreground animation.** After each update the window captures the SwiftUI animation for one second, at six frames per second by default, also while a table in the app is scrolling. Reduce Motion disables it, and so does `PiPControllerSlot(animationFramesPerSecond:)` with `nil`, zero or a negative value.
- **Configurable background.** `PiPControllerSlot(backgroundColor:)` sets the opaque color behind the content, black by default; the images carry no transparency.
- **Invisible in the app.** The off-screen copy of the content that feeds the PiP window is hidden from VoiceOver.
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

The example uses your own `GaugeView` and `GaugeModel` types. Keep the `GaugePiP` owner alive for the session and subscribe to `exits` to call `stop(completion:)` and clear your app's session state after an external close or failed start.

```swift
import AVFoundation
import Combine
import MRPiPKit
import SwiftUI

@MainActor
final class GaugePiP {
    /// `PiPControllerSlot(animationFramesPerSecond: nil)` renders only explicit updates; `backgroundColor:` replaces the
    /// black behind the content.
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
        // Wait for teardown to finish, or for its timeout to discard the pipeline.
        slot.deactivate(completion: completion)
    }
}
```

The kit drives one PiP per slot. Which PiP is active, the handoff between them and the audio session belong to your app.

Start a replacement session from the completion of `deactivate(completion:)`, when the slot is available again. Explicit stops do not emit an exit event. In background, call `scheduleRendering()` whenever your model changes: the foreground animation timer does not run there.

`didFail` receives `PiPStartRejectedError` when a slot still has an active controller, or one still closing: close your session in that case, because no window will report its end, and start the next session from the completion of `deactivate(completion:)`. Any other error means AVKit did not show the window; an exit follows.

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
