# Engine inset pipeline: can the main engine's widget tree share the keyboard's display frame?

- Date: 2026-11-10
- Lane: mechanism research (read-only; no commands, no builds, no device/simulator run)
- Author: engine-pipeline (subagent)
- Question: when the plugin writes the engine's bottom view inset from its pan handler /
  CADisplayLink (`updateViewportMetricsWithInset:`, `targetViewInsetBottom`,
  `invalidateKeyboardAnimationVSyncClient`), does Scaffold/ListView receive that value in the SAME
  display frame that UIKit commits the keyboard's new position, or structurally one frame later?
- Engine: local checkout `/Users/vitekvitek/development/flutter/engine/src/flutter`, Flutter 3.47.7
  stable, engine `deb287481e3ce9468f3434937ced4240a70539ca` (`bin/internal/engine.version:1`,
  `bin/cache/flutter.version.json:2-9`). Framework: same SDK, `packages/flutter`. dart:ui: the SDK's
  `bin/cache/pkg/sky_engine` copy.
- Repo under study: this tree (`cupertino_interactive_keyboard` 1.1.3).

## Verdict

**Yes: the list's laid-out edge lands one display frame after the keyboard/bar edge, structurally —
but not for the reason H1 gives.** The platform→UI handoff is a *posted, non-blocking* task
(`fml/task_runner.cc:68-81`), and the framework consumes it in the first frame whose build begins
after that task runs — normally the next vsync's frame, with no extra frame lost there. The extra
frame comes from the *render/present* side: the frame that consumes the write is built at vsync N and
its pixels are only committed to Core Animation on a later main-thread turn
(`FlutterMetalLayer.mm:398-445`), i.e. shown at N+1, while a UIView/NSLayoutConstraint change made
from the same value is CA-committed in the same runloop turn and shown at N. So for one and the same
inset value, the native bar edge is on screen one vsync before the Flutter-rendered list edge.

The engine's own keyboard animation is *not* one frame late, and that is the tell: it writes the inset
for the **next presentation time** (`projectedTargetTime = targetTime + frameInterval`,
`FlutterKeyboardInsetManager.mm:393-403`), and its comment says why ("Make sure the new viewport
metrics get sent after the begin frame event has processed"). The plugin's drag writes are
*current-sample* values with no such projection (`KeyboardManager.swift:478-540`), so they are
always one frame behind the bar/keyboard they describe.

Cadence summary:

| producer | runloop / thread | tick | locator |
|---|---|---|---|
| keyboard drag (UIKit) | main | touch delivery, model position applied in the pan handler | repo `KeyboardManager.swift:168-189` comment; iOS behaviour |
| plugin inset writer | main | gesture action + one main-queue turn later + one `CADisplayLink` on `.main` | `KeyboardManager.swift:173-189, 232-234, 441-468` |
| engine vsync (BeginFrame) | UI task runner runloop (`CADisplayLink` added to `.current` of that runner) | every display refresh | `VSyncClient.swift:72-75`; `vsync_waiter_ios.mm:38-45` |
| engine keyboard-inset animation | UI runner `CADisplayLink` -> `dispatch_async` main -> write | every refresh, value projected **one frame ahead** | `FlutterKeyboardInsetManager.mm:385-411, 349-383` |
| engine present (CA layer contents) | main thread, `CATransaction`, driven by the layer's own main-runloop `CADisplayLink` | every CA frame | `FlutterMetalLayer.mm:34-36, 398-445` |

## Timeline of one drag frame (the mechanism)

Write made during interval (t, t+1) — the normal case for the plugin's touch-time write:

| time | main thread | UI thread |
|---|---|---|
| (t, t+1) | pan handler: `barInset` computed, bar bottom constraint set + `layoutIfNeeded` (CA commits at end of this turn), inset written | posted task runs: `UpdateViewMetrics` -> Dart `_updateWindowMetrics` -> `onMetricsChanged` -> `RenderView.configuration` + `MediaQuery` `setState` -> `scheduleFrame` -> `Animator::RequestFrame` -> `AwaitVSync` |
| t+1 | **keyboard + bar pixels shown** (CA commit from (t, t+1)) | BeginFrame: build/layout with the new inset |
| t+2 | present (`presentTexture` -> main queue -> `self.contents`) | frame pixels committed |

If the write is made *at* the vsync instead of between vsyncs (the `CADisplayLink` path,
`KeyboardManager.swift:232-234`), the metrics task can arrive after that vsync's BeginFrame has
started on the UI thread; then it is consumed at t+2 and shown at t+3 — one worse. The repos own design
doc states the practical version of this (`docs/superpowers/specs/2026-11-09-keyboard-accessory-sync-design.md:18-21`:
*"A write of the viewport inset made from a CADisplayLink is one frame too late"*); the source-level
caveat is that the engine's vsync and the plugin's display link live on **different runloops** (UI task
runner vs main), so their relative order is not defined — the write is safe only when it happens before
the frame's build, which the touch-time write normally does and a vsync-time write does not.

## (a) Platform -> UI threading, and how far the value travels

1. Plugin -> engine (private selector, same call shape the engine uses):
   `KeyboardManager.swift:564-580` calls `-updateViewportMetricsWithInset:`.
2. `FlutterViewController.mm:2312-2315`: writes `_viewportMetrics.physical_view_inset_bottom = inset`
   and calls `updateViewportMetricsIfNeeded` (`:1368-1375`), which pushes the **whole**
   `ViewportMetrics` struct to `-[FlutterEngine updateViewportMetrics:]`.
3. `FlutterEngine.mm:385-390` -> `platformView->SetViewportMetrics(kFlutterImplicitViewId, ...)`
   (`shell/common/platform_view.cc:59-62`) -> `Shell::OnPlatformViewSetViewportMetrics`
   (`shell/common/shell.cc:1131-1160`).
4. **The handoff is asynchronous, not synchronous.** `shell.cc:1154-1160` uses
   `fml::TaskRunner::RunNowAndFlushMessages(uiTaskRunner, ...)`; since the caller is the platform
   thread, `fml/task_runner.cc:68-81` takes the else branch: `runner->PostTask(task)` — it does
   **not** run the task or block. (This corrects `docs/audit/2026-11-09-engine.md:99-106`, which calls
   it "one blocking platform->UI handoff": it is one posted task, ~one task turnaround, and it does not
   block the main thread. The engine's per-frame relayout cost is therefore not a main-thread stall.)
5. On the UI thread: `Engine::SetViewportMetrics` (`shell/common/engine.cc:346-350`) ->
   `RuntimeController::SetViewportMetrics` (`runtime/runtime_controller.cc:228-238`) ->
   `PlatformConfiguration::UpdateViewMetrics` (`lib/ui/window/platform_configuration.cc:199-250`).
6. `UpdateViewMetrics` calls the Dart `updateWindowMetrics` closure with the raw metrics
   (`platform_configuration.cc:209-249`, `physical_view_inset_bottom` at `:228`). In Dart,
   `PlatformDispatcher._updateWindowMetrics` stores the `ViewConfiguration` and immediately
   `_invoke(onMetricsChanged)` (`sky_engine/lib/ui/platform_dispatcher.dart:332-339`). Everything
   below runs synchronously inside that one posted task.
7. `RendererBinding.handleMetricsChanged` (registered at `rendering/binding.dart:58`) walks the
   `RenderView`s, sets `view.configuration = createViewConfigurationFor(view)` and calls
   `scheduleForcedFrame()` (`rendering/binding.dart:399-413`). The `RenderView.configuration` setter
   calls `markNeedsLayout()` (`rendering/view.dart:171-188`); layout itself happens in
   `RenderView.performLayout` on the next frame (`rendering/view.dart:288-296`).
8. `WidgetsBinding.handleMetricsChanged` then notifies observers (`widgets/binding.dart:921-940`).
   The relevant one is the `MediaQuery` that `View` installs above the app
   (`widgets/view.dart:269-294`): `_MediaQueryFromViewState.didChangeMetrics` -> `_updateData` ->
   `setState` (`widgets/media_query.dart:2353-2395, 2408-2411`), where `MediaQueryData.fromView`
   reads `view.viewInsets` / `devicePixelRatio` (`widgets/media_query.dart:300-309`).
9. `Scaffold` consumes it at build: `minInsets.bottom = MediaQuery.viewInsetsOf(context).bottom`
   (`material/scaffold.dart:3219-3230`) and `_ScaffoldLayout.performLayout` computes
   `contentBottom = bottom - max(minInsets.bottom, bottomWidgetsHeight)` and lays the body out to
   `bodyMaxHeight = contentBottom - contentTop` (`material/scaffold.dart:1085-1114`).
   So: the *state* is current within the posted task; the *body/viewport height* changes at the next
   frame's build/layout. No hidden deferral exists in the framework path.

**Answer to (a):** platform->UI is one posted task (sub-millisecond, non-blocking); the framework's
`viewInsets`/MediaQuery/Scaffold chain has no extra frame of its own — it is all consumed by the next
frame. The write does not have to wait for a "later UI task"; it has to be *before the next build*.

## (b) Frame scheduling on iOS: engine vsync, CADisplayLink, touch delivery, and what the private calls do

- **Engine frame vsync is on the UI task runner's runloop, not the main runloop.** `VsyncWaiterIOS`
  builds a `FlutterVSyncClient` with the UI task runner (`vsync_waiter_ios.mm:38-45`), and the client
  adds its `CADisplayLink` to `NSRunLoop.current` on the posting thread (`VSyncClient.swift:72-75`).
  `AwaitVSync` unpauses it (`vsync_waiter_ios.mm:54-61`). The callback carries
  `link.timestamp` (this vsync) and `link.targetTimestamp` ("the anticipated presentation time of the
  next screen refresh", `VSyncClient.swift:170-176`) — the projection basis in (c).
- **The presented pixels are committed separately, on the main thread.** `FlutterMetalLayer` exists
  because "there must be a CADisplayLink scheduled *on main thread* otherwise core animation only
  updates layers 60 times a second" (`FlutterMetalLayer.mm:34-36`), and its own comment states the
  UI-thread vsync "does not trigger actual core animation frame" (`:203-207`). Raster thread ->
  `presentTexture:` -> `dispatch_async(main)` -> `presentOnMainThread` sets `self.contents` inside a
  `CATransaction` (`:398-445`). A frame built at vsync N therefore becomes a committed layer at some
  point after N and is shown at the following vsync — the structural half-frame-to-one-frame step.
- **Touch delivery and keyboard notifications are main-thread, `CADisplayLink` is main-thread for the
  plugin (`KeyboardManager.swift:232-234` after `add(to: .main, forMode: .common)`), and the engine's
  vsync is UI-thread.** Ordering between the plugin's tick and the engine's BeginFrame is a race, not
  an order. The plugin deliberately writes from the gesture action ("UIKit has normally already applied
  the drag by the time the gesture action runs", `KeyboardManager.swift:168-189`) plus one
  `DispatchQueue.main.async` turn, which is the only write timing that reliably precedes the frame.
- **`updateViewportMetricsWithInset:` does: write the field + push full metrics + (via
  `Engine::SetViewportMetrics`) schedule one frame.** No animation, no throttle, no coalescing beyond
  `Animator::RequestFrame`'s single-pending-frame semaphore (`shell/common/animator.cc:239-271`;
  multiple requests still produce one `AwaitVSync`). `ScheduleFrame` is
  `engine.cc:346-350 -> :510-512 -> animator_->RequestFrame()`; `RequestFrame` posts `AwaitVSync`
  "right after an idle" on the UI runner precisely so it does not run in the middle of a callout
  (`animator.cc:256-269`). **It writes the target, it does not animate, and it does schedule a frame.**
- **`setTargetViewInsetBottom:` writes only the dedupe/animation-end field** (readwrite extension
  `FlutterKeyboardInsetManager.mm:20`; read at `:67, 87, 296, 346, 426`). It schedules nothing.
- **`invalidateKeyboardAnimationVSyncClient`** (`FlutterKeyboardInsetManager.mm:413-416`) invalidates
  the client and nils it; `VSyncClient.invalidate` hops to the creating (UI) thread to invalidate the
  link (`VSyncClient.swift:130-145`). It stops the *writer*; it schedules no frame.

## (c) The engine's inset animation during an interactive dismissal, and whether the pokes cancel it

- **During the drag the engine is a no-op by design.** The notifications posted while the keyboard is
  dragged have a zero `UIKeyboardFrameEndUserInfoKey`; `shouldIgnoreKeyboardNotification:` returns
  `YES` for exactly that case (`FlutterKeyboardInsetManager.mm:100-110`). No animation is started, no
  inset is written, `targetViewInsetBottom` is untouched — H3 ("the engine's animation competes")
  does not apply during the drag; the engine only becomes active on notifications it does not ignore.
- **On those notifications the plugin has already stopped tracking** (swizzle runs the plugin's
  hand-off before the original handler: `FlutterViewController+Swizzle.swift:46-60`), so the engine
  animates from `physicalViewInsetBottom` — the plugin's last write (`FlutterKeyboardInsetManager.mm:273-276`).
- **What the animation is:** a hidden 0x0 `UIView` animated with UIKit's own duration/curve
  (`:287-303`); per vsync the manager reads its presentation-layer y (or a spring curve) and calls
  `updateViewportMetricsWithInset:` (`:349-383`). The value written is the view's position **at
  `projectedTargetTime = targetTime + frameInterval`**, and the callback itself is
  `dispatch_async`d to the main queue with the comment "Make sure the new viewport metrics get sent
  after the begin frame event has processed" (`:393-403`). That is the engine compensating for exactly
  the write-to-layout latency measured in (b): it writes one frame into the future on purpose.
- **Do the pokes cancel it fully?** While tracking: yes for writes. `invalidateEngineAnimationIfNeeded`
  runs once per session before the first write (`KeyboardManager.swift:625-646`); the client is nil'd,
  so no per-vsync callback survives, and the animation's completion block refuses to write because its
  captured client is no longer the current one (`FlutterKeyboardInsetManager.mm:304-313`), which also
  makes the "compounding" branch unreachable (`:78-79` requires a non-nil client). Residual state:
  the hidden view's UIKit animation object and `keyboardAnimationIsShowing` stay behind until the next
  animation starts (`:259-267`) or the manager is invalidated — no write path, harmless.
  **One path is not covered by the invalidate**: a `WillHide` with `duration == 0` reaches
  `hideKeyboardImmediately` (`:56-64, 317-329`), which writes the target (0) in one frame with no
  animation. The plugin now intercepts it before the engine sees it (`ownsInstantCollapse` /
  `ownedCollapseTransition`, `KeyboardManager.swift:361-397`, called at
  `FlutterViewController+Swizzle.swift:52-55`) — that is the one engine path that would otherwise
  inject a one-frame step larger than any timing error.

## (d) ProMotion / 120 Hz, and the per-frame travel math

- On ProMotion iPhones 120 Hz is locked unless the app sets `CADisableMinimumFrameDurationOnPhone`
  to `true` in Info.plist (`DisplayLinkManager.swift:15-17`, key at `:24-28`, read at `:38-41`;
  `VSyncClient.setMaxRefreshRate` early-returns when it is not enabled, `VSyncClient.swift:89-91`;
  the CA layer has the same gate, `FlutterMetalLayer.mm:203-215`). iPad Pro is 120 Hz by default.
  The plugin's example app sets the key to true (`example/ios/Runner/Info.plist:5-6`); an app without
  it runs the whole pipeline at 60 fps and doubles the visible error per frame.
- The engine reports the refresh rate from the link's own duration each tick
  (`VSyncClient.swift:183-196`) and sets `preferredFrameRateRange` min 60 / max+preferred = max
  refresh rate (`:93-101`) — so a ProMotion device with the key runs 120 Hz, without it 60 Hz.
- Travel per frame = keyboard velocity x frame interval. With the docked height measured on the owner's
  device in the instant-hide trace (329.6 -> 0 in one step,
  `docs/superpowers/specs/2026-11-10-hosted-bar-ownership-design.md:116`), i.e. D ~ 330 pt:

| gesture | duration | velocity | 60 Hz (16.7 ms) | 120 Hz (8.3 ms) |
|---|---|---|---|---|
| fast flick, full dismissal | 100 ms | 3.3 pt/ms | ~55 pt/frame | ~27 pt/frame |
| fast drag, 40% then release | 250 ms | 1.3 pt/ms | ~22 pt/frame | ~11 pt/frame |
| normal drag | 400 ms | 0.8 pt/ms | ~14 pt/frame | ~7 pt/frame |

One frame of mismatch is therefore **not** a 1-2 pt jitter: at 60 Hz it is a 20-60 pt band, exactly the
size of the reported "clipped message line + background band". The same numbers are what the engine
projects away for its own animation and what the plugin does not project for the drag.

## (e) The one probe line that proves or kills the structural one-frame claim

CIKTrace already logs every inset write with the engine read-back (`KeyboardManager.swift:553-556`,
`inset=... engine=...`) and the bar's change-only layout against the guide
(`CIKHostedAccessoryBar.swift:155-169`, `bar bottom=... guideTop=...`). What is missing is **which
frame consumes the write and when that frame is presented**. Add exactly one native line and its Dart
twin, both in the same wall-clock unit:

Native, at the top of `trackInteractiveKeyboard()` (`KeyboardManager.swift:441-468`), which already
runs on the main-runloop CADisplayLink, i.e. in the CA commit phase:

```swift
CIKTrace.log("frame", "epoch=\(Date().timeIntervalSince1970 * 1000) t=\(CACurrentMediaTime()) "
  + "target=\(link.targetTimestamp) inset=\(CIKTrace.points(readPhysicalViewInsetBottom())) "
  + "barModel=\(CIKTrace.points(hostedAccessoryBar?.frame.maxY)) "
  + "barPresented=\(CIKTrace.points(hostedAccessoryBar?.layer.presentation()?.frame.maxY)) "
  + "guideTop=\(CIKTrace.points(guideTopInView()))")
```

Dart twin, one line per metrics push (a `WidgetsBindingObserver.didChangeMetrics` in the plugin's debug
helper; this is the only place where frame identity exists):

```dart
debugPrint('[CIKTrace] metrics epoch=${DateTime.now().millisecondsSinceEpoch} '
  'frame=${WidgetsBinding.instance.frameNumber} phase=${WidgetsBinding.instance.schedulerPhase} '
  'insets=${MediaQueryData.fromView(View.of(context)).viewInsets.bottom}');
```

Decision rule, on a fast drag:

- `phase == idle || postFrameCallbacks` and the `insets` value equals the write whose `epoch` is in
  the previous vsync interval => the framework does **not** lose a frame; the list's lag is the present
  step only (this note's claim).
- `phase == transientCallbacks || persistentCallbacks` => the write landed inside a frame that was
  already being built (the CADisplayLink-race case) and **that** frame is lost; the claim would then be
  "one frame lost by write ordering", fixable by moving the write off the vsync boundary, not by
  restructuring the engine pipeline.
- `inset` at every tick equals the last write but `barPresented` and the list's bottom edge (Dart:
  log the list's `GlobalKey` render box bottom) differ by the per-frame travel in the same tick =>
  the visible band is the render/present step; nothing in the metrics path can remove it.
- If `insets`/list bottom and `barPresented` agree within 0.5 pt on every tick, the structural claim is
  **dead**: the band is arithmetic (reserved height vs real bar height, H4) or ordinary viewport
  clipping (H6).

## Evidence

| id | type | locator | credibility | proves |
|---|---|---|---|---|
| E1 | engine source read | `engine/src/flutter/fml/task_runner.cc:68-81` | high — primary fml implementation | `RunNowAndFlushMessages` only runs inline when already on the target thread; from the platform/main thread it is a plain `PostTask` — the metrics handoff is async and non-blocking (kills the "blocking handoff / main-thread stall" reading in the repo audit). |
| E2 | engine source read | `shell/common/shell.cc:1131-1160` | high — primary | The platform thread forwards viewport metrics to the UI runner as a task; validates metrics first; the inset reaches the engine exactly one UI task later, with no throttle. |
| E3 | engine source read | `lib/ui/window/platform_configuration.cc:199-250` (+ `:228`) | high — primary | The UI task invokes the Dart `updateWindowMetrics` closure synchronously with `physical_view_inset_bottom`; no further queueing in the engine. |
| E4 | framework source read | `packages/flutter/lib/src/rendering/binding.dart:58, 399-413`; `rendering/view.dart:171-188, 288-296` | high — primary framework | On the metrics callback the binding sets `RenderView.configuration` (which only `markNeedsLayout`s) and calls `scheduleForcedFrame`; layout happens in the next frame. |
| E5 | framework source read | `packages/flutter/lib/src/widgets/view.dart:269-294`; `widgets/media_query.dart:300-309, 2353-2395, 2408-2411` | high — primary framework | `View` puts `MediaQuery.fromView` above the app; `didChangeMetrics` -> `setState` -> rebuild in the scheduled frame; `viewInsets` is read from `FlutterView` at rebuild time. |
| E6 | framework source read | `packages/flutter/lib/src/material/scaffold.dart:3219-3230, 1085-1114` | high — primary framework | Scaffold derives the body height from `viewInsets.bottom` at build and lays the body out to it, so the list viewport's bottom edge moves exactly when this rebuild+layout runs. |
| E7 | engine source read | `shell/platform/darwin/ios/framework/Source/FlutterKeyboardInsetManager.mm:393-403` | **high — the critical item** | The engine explicitly sends inset writes *after* the begin frame ("Make sure the new viewport metrics get sent after the begin frame event has processed") and therefore evaluates the animation one frame interval in the future; the write-to-layout latency of one frame is assumed by the engine itself. |
| E8 | engine source read | `FlutterKeyboardInsetManager.mm:287-303, 349-383`; `.h:64-106` | high — primary | The engine's own transition is a hidden UIView animated with UIKit's curve, sampled per vsync and pushed as metrics; the value pushed is a projection, not the current position. |
| E9 | engine source read | `FlutterViewController.mm:2312-2315, 1368-1375` | high — primary | The private poke writes `physical_view_inset_bottom` and pushes the whole metrics struct; it is exactly the engine's own write path, with no animation and no scheduling of its own. |
| E10 | engine source read | `shell/common/engine.cc:346-350, 510-512`; `shell/common/animator.cc:239-289` | high — primary | One metrics write schedules at most one frame (`Animator::RequestFrame` semaphore) and `AwaitVSync` is posted after an idle; a write cannot piggy-back on a frame already being built. |
| E11 | engine source read | `shell/platform/darwin/ios/framework/Source/VSyncClient.swift:72-75`; `vsync_waiter_ios.mm:18-45, 54-61`; repo `KeyboardManager.swift:232-234` | high — primary | The engine's vsync CADisplayLink lives on the UI task runner's runloop while touch handling and the plugin's CADisplayLink live on the main runloop: their order at a vsync is unspecified, so a vsync-time write loses the frame race. |
| E12 | engine source read | `FlutterMetalLayer.mm:34-36, 203-215, 398-445` | high — primary; medium only for the exact vsync it lands on | The rasterized frame becomes a CA layer commit on a later main-thread turn inside a `CATransaction`, driven by a main-runloop CADisplayLink; a frame built at vsync N is shown at N+1, one vsync after the native bar/keyboard edge committed in the same write turn. |
| E13 | repo file read | `ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/KeyboardManager.swift:173-189, 232-234, 441-468, 478-540, 543-557` | high — repo source | The plugin writes (a) from the gesture action, (b) one main-queue turn later, (c) from a main-runloop CADisplayLink, always the *current* sampling of the band, and writes the same `barInset` to the bar constraint and the engine inset. |
| E14 | repo file read | `KeyboardManager.swift:564-580, 586-600, 608-622, 625-646` | high — repo source | The three private pokes are exactly `updateViewportMetricsWithInset:`, `physicalViewInsetBottom`, `setTargetViewInsetBottom:`, `invalidateKeyboardAnimationVSyncClient` — no animation or scheduling of their own; the invalidation is once per tracking session. |
| E15 | repo file read (absence) | grep of `ios/` for `physicalViewInsetBottom`: only `ownsInstantCollapse`/trace (`KeyboardManager.swift:371, 386, 555`) — no display-link read used to position the bar, contrary to `docs/superpowers/specs/2026-11-10-hosted-bar-ownership-design.md:130-138` | high — the tree is the artifact | In this tree the bar edge and the engine inset are driven from the *same* `barInset` in the same call; the bar edge is a CA constraint (shown at N) and the list edge is Flutter-laid-out (shown at N+1), which is the mechanism of the visible separation. |
| E16 | repo doc read | `docs/superpowers/specs/2026-11-09-keyboard-accessory-sync-design.md:18-21` | medium — repo reasoning, no source locator | The plugin team already concluded a CADisplayLink-time write is one frame late and moved the write to touch time; the doc's stated cause ("the engine's vsync callback runs before the plugin's display link callback") is a runloop-order assumption, not a guarantee (see E11). |
| E17 | engine source read | `FlutterKeyboardInsetManager.mm:56-64, 100-110, 304-313, 413-416, 424-427` | high — primary | During a drag the engine ignores zero-frame frame-change notifications (no animation, no write); an invalidated vsync client cannot write and its completion block is neutered by the client identity check; the only unanimated writer left is the duration-0 hide path. |
| E18 | engine source read | `DisplayLinkManager.swift:15-41`; `VSyncClient.swift:89-105, 155-201`; repo `example/ios/Runner/Info.plist:5-6` | high — primary + repo plist | ProMotion 120 Hz requires `CADisableMinimumFrameDurationOnPhone`; a 60 Hz app has twice the per-frame keyboard travel of a 120 Hz one, so the same one-frame error is twice as visible. |
| E19 | repo doc read | `docs/audit/2026-11-09-engine.md:91-120` | medium — accurate on the chain, wrong on sync/blocking; superseded by E1 | The audit's chain (selector -> `SetViewportMetrics` -> `RunNowAndFlushMessages` -> `Engine::SetViewportMetrics` -> `ScheduleFrame`) is right, but its "blocking platform->UI handoff" and "one blocking handoff per drag event" are not (E1). |
| E20 | framework source read | `packages/flutter/lib/src/rendering/viewport.dart:973-980` | high — primary framework | The viewport clips to its own bounds, so once the viewport bottom is displaced from the composer top a message line is cut at that edge exactly — the artefact's "cut line" needs no extra bug. |

## What is ruled out

- **H1 as stated (the platform->UI task is what costs the list a frame).** The task is a non-blocking
  post (E1) and the framework consumes it in the next build (E4-E6). No queueing delay of a frame
  exists inside the write path. The one-frame gap is real but comes from the render/present step
  (E7, E12) and from the plugin writing current rather than projected values (E7, E13).
- **H3 (the engine's own inset animation still competes during the drag).** The engine ignores the
  zero-frame drag notifications (E17) and never starts an animation; the plugin's invalidation is a
  belt-and-braces measure for a drag that starts while a show animation is running (E14, E17).
- **"The framework defers MediaQuery/viewInsets by a frame."** Nothing in the framework path defers it
  (E4-E6); the delay is in when the *pixels* exist, not in when the *state* exists.
- **"The main thread blocks on each write, so the drag is janky because of the inset writer."** Only
  true for one main-queue task turnaround, not a blocking UI handoff (E1).
- Not decided by this lane (handed to the layout/geometry and prior-art lanes): H2 (is the per-frame
  build/layout actually too expensive — a frame-time measurement, not a source fact), H4 (reserved
  height vs real bar height, and the mid-drag 34 pt safe-area change), H5 (UIKit/guide sampling
  staleness), H6 (whether the band is pure clipping — it needs the geometry inequality, but the clip
  itself is expected, E20).

## The one critical evidence item

**E7** — `FlutterKeyboardInsetManager.mm:393-403`: the engine writes the inset only after the begin
frame has been processed and therefore evaluates the keyboard animation one frame in the future
(`projectedTargetTime = targetTime + frameInterval`). That is the engine's own statement that an inset
write is consumed by the *next* frame, and its own compensation shows the size of the correction: one
display frame. Combined with E1 (the write is posted, not inline) and E12 (present is a later
main-thread CA commit), it means the plugin's current-value drag writes cannot be in the keyboard's
present frame, while an inset written one frame ahead of the presentation time could be.

## Confidence

- **High** on (a) threading, (b) what each private call does, (c) engine behaviour plus the fact that
  the pokes stop the engine's writes: all primary engine/framework source at the pinned revision.
- **Medium-high** on the structural one-display-frame claim: the write-to-layout half is proven by E7
  (the engine says so itself); the present half (a frame built at vsync N is shown at N+1 while a CA
  constraint change made in (N-1, N) is shown at N) is inferred from the present path (E12) and vsync
  semantics, not measured here (no device run allowed). The measured probe in (e) is what upgrades or
  kills it.
- **Medium** on the visible-band magnitude: the per-frame travel math (d) is exact given D ~ 330 pt,
  but the observed band also carries the app-side reservation arithmetic (H4) and any UIKit sampling
  staleness (H5), which this lane did not evaluate.
- Direction of the conclusion: it *supports* "the list is one frame behind", which is H1's symptom,
  but *contradicts* H1's mechanism and therefore the class of fixes H1 implies (there is nothing to
  "sync" in the platform->UI hop; the lever is the value written relative to the presentation time, or
  moving the list edge out of the Flutter layout path).
