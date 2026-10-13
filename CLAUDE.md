# CLAUDE.md

Guidance for coding agents working on MRPiPKit. Read `~/.claude/CLAUDE.md` first, then this file. Talk to the user in Italian.

## What this package is

A generic, reusable Picture in Picture library for live SwiftUI content on iOS and Mac Catalyst, built directly on AVKit. It was extracted on 2026-10-13 from Device Monitor², which replaced PIPKit with it, and it must stay usable by any other app.

Its only consumer today is Device Monitor², at `../Device Monitor`. That app's `AGENTS.md` describes how it uses the kit and holds the history of the lifecycle decisions in its PiP paragraphs: read them before changing the lifecycle.

## Hard rules

- **Keep it generic.** No types, strings, stores, purchases, providers or policies of any app. Which PiP is active, handoffs between PiPs and the audio session belong to the app.
- **Minimal public API.** Make public only what an app needs. Today Device Monitor² uses: `PiPHostingViewController.init(rootView:animationFramesPerSecond:)`, `restoreInterface`, `applyLayout(size:)`, `scheduleRendering(continuously:)`, `startPictureInPicture()`; `PiPControllerSlot.init(animationFramesPerSecond:)`, `active`, `exitPublisher`, `activate(interfaceStyle:size:transitionDidChange:didFail:makeContent:)`, `deactivate(completion:)`; `PiPStartRejectedError`; `PiPKitLog.handler`. Changing any of them means updating the app's four providers and `PiPManager` in the same task.
- **No `#if`.** `Package.swift` declares the platforms.
- **Swift 5 language mode**, like the app (`swiftLanguageModes: [.v5]`). Do not switch to Swift 6 mode without the user's request and a build.
- **Tools version 6.4** (Xcode 27.1): the iOS 27 SDK is required to compile the receiver path even when deploying to iOS 18. Availability annotations do not stop older SDKs from type-checking it, so raise the tools version rather than adding `#if`.
- **Never run builds** (`swift build`, `xcodebuild`, the app's check scripts) unless the user explicitly asks. Verify statically and say what was not compiled.
- **No locks** (`NSLock`, `os_unfair_lock`, semaphores used as locks). Use main-actor isolation, actors and single-owner state.
- **No third-party dependencies.**
- **Never commit.** The user commits. The package is not a git repository yet.
- **Format** after every Swift change, with the app's configuration, from this folder:

  ```
  swiftformat . --config "../Device Monitor/.swiftformat"
  ```

- **New Swift files** start with this header, with the versions actually in use (`swift --version`, `sw_vers`):

  ```swift
  //
  //  FileName.swift
  //  MRPiPKit
  //
  //  Created by Marco Ricca on DD/MM/YYYY
  //
  //  Created for MRPiPKit in DD/MM/YYYY
  //  Using Swift <version>
  //
  //  Copyright © 2026 Fast-Devs Project by Marco Ricca. All rights reserved.
  //
  ```

## Structure

| Folder | Contents |
|---|---|
| `Host` | `PiPHostingViewController.swift`: public interface, session state and the AVKit delegate methods. `+Startup`: source, readiness, deferred request, startup timeouts and silent-start recovery. `+Stopping`: closing, renewals, background release and receiver teardown. `+Rendering`: foreground snapshots, direct renders and buffers. `PiPSessionPhase`, `PiPTimings`. |
| `Rendering` | The two sample buffer paths (before and from iOS 27) behind `makePiPSampleBufferRendering(for:)`, the JPEG sample buffer factory, the bitmap renderer and the animation display link. |
| `Slot` | `PiPControllerSlot`: start sequence, exit forwarding, stop and reuse of the hosting controllers. |
| `Support` | `PiPKitLog`, errors, the window lookup and `awaitWithTimeout`. |

- The AVKit delegate methods must stay in the class body: Objective-C members cannot live in extensions of a generic class. Pure Swift lifecycle code goes in the extensions.
- Session state is internal, not private, only so the extensions in sibling files can reach it. Nothing outside the controller may touch it; the slot uses only `configureView`, `anchorOffscreen`, `stopPictureInPicture(completion:)`, `canRestartPictureInPicture`, `exitPublisher`, `didFail`, `transitionDidChange` and `restoreInterface`.
- Every time limit lives in `PiPTimings`.

## Lifecycle invariants

- `PiPSessionPhase` is the only lifecycle state. Every AVKit callback and every entry point guards or switches on it; never add parallel flags for what a phase can express.
- `closingRetention` makes the controller retain itself while closing, so the slot and the owner may detach at once. For every lifecycle change, check who retains the controller until its stop completion runs: a past review found a controller deallocated with its stop completion still queued.
- An explicit stop (`markExplicitStop()`) emits no exit event and cancels the silent-start recovery. Exits that the owner did not ask for go through `exitSubject`, which the slot forwards.
- A stop after WillStart moves to `cancellingStart`: the source stays attached until DidStart closes the window, a start failure, or one more startup timeout. Detaching earlier leaves a window nobody closes, the bug that PIPKit had.
- In background AVKit answers no `stopPictureInPicture()`: an explicit stop made in background, or still waiting when the app enters the background, releases at once without renewals and discards that controller. The release closes the window. This was observed on device on 2026-10-12 and 2026-10-13.
- `releaseRendering()` invalidates AVKit's source and delegate before the asynchronous receiver flush, bounded by `PiPTimings.teardownTimeout`. Only `finishReleasingRendering()` returns to `.idle` and runs the stop completions.
- A controller is reusable only after a confirmed DidStop and a complete teardown (`canReuseController`). The slot clears the callbacks of an idle controller, gives a reused one the current activation's `makeContent()` as `rootView`, and drops it on a memory warning.
- `transitionDidChange` is balanced: `true` from `startPictureInPicture()` and on every closing step, `false` from `confirmStart` or at the end of `finishReleasingRendering()`. The only unbalanced edge is the silent-start recovery, which skips the `false` because it restarts at once with a new `true`. Trace every new path against this.
- The source goes into the best scene with windows (foreground active, then foreground inactive, then the rest), then into its key or last window. Foreground inactive must stay accepted: a system sheet shown by the owner, such as a capture picker, keeps the app inactive while the start begins.
- Foreground updates send the hosting layer's animation frames through the display link, in the common run-loop modes. Background updates render the SwiftUI model directly, because the hosting layers can be frozen there. `animationFramesPerSecond: nil` disables the animation frames, for content whose own redraws matter, like a screen-capture readout.
- The private `controlsStyle` key stays, behind a `responds(to:)` check. The user chose to keep it.

## Logging

`PiPKitLog.d` sends lines to `PiPKitLog.handler`, which Device Monitor² points at its own log. The existing lines are in Italian, and their wording must stay stable: the app's device checklist and `AGENTS.md` quote them, for example "rilascio senza attendere AVKit". Write new lines in Italian in the same style.

## Verifying a change

- There are no automated tests: AVKit's PiP does not run in tests or reliably in the simulator. Trace every change by hand, phase by phase, and include who retains the controller.
- For refactors, compare each method body before and after, ignoring indentation and comments, and justify every difference.
- Device checks live in the app, in `../Device Monitor/Tests/DisplayPiP-device-checklist.md`. That folder is git-ignored, by the user's choice. List which checks a change needs.
- After changing the public API, search the app for every use and update it.
