# Coding research: the chat list falls a frame behind the keyboard and is cut at its viewport edge during a fast interactive drag

- Lane: coding
- Date: 2026-11-10
- Decision: Choose how to remove the list's lag and clipped bottom edge relative to the keyboard and the native composer during a fast interactive keyboard drag, for the plugin owner, under the constraints that the bar stays a live Flutter widget in a second engine, the main app keeps one engine, and the interactive dismissal keeps its current feel.
- Confidence: medium - the leading mechanism is primary-source on the write side and inferred on the present side (no device run was permitted), a second producer is confirmed by an earlier device trace, and jank cannot be excluded without a frame-time trace.
- Written to: docs/research/2026-11-10-keyboard-drag-list-lag.md

## Symptom

On the hosted-accessory example screen (Scaffold -> Column -> Expanded(ListView(reverse: true)) -> CupertinoKeyboardAccessory, `example/lib/keyboard_accessory.dart:155-175`), dragging the keyboard down fast makes the list's bottom edge fall behind the composer/keyboard: the last visible line of the message bubble is cut at the list's viewport edge, and a strip of app background separates that cut edge from the native composer above the keyboard. The composer itself stays glued to the keyboard. The owner supplied one frame of the screen recording (`IMG_7155.png`, 2026-11-10, DEBUG build); the band in that frame is roughly 50-85 pt depending on how the phone screen is scaled, and the composer has no gap to the keyboard.

Reproduction status: **not reproduced by this researcher** - no simulator or device run was permitted in this session. Evidence used instead: the owner's frame, the owner's report ("when fast dragging ... the list lags behind, and clips weirdly"), the device traces already recorded in this repo's design addenda (`docs/superpowers/specs/2026-11-10-hosted-bar-ownership-design.md:112-124`), and primary engine/framework source at the pinned Flutter 3.47.7 revision. What was tried: nothing was executed; the owner had already tried `resizeToAvoidBottomInset: false` and manual list padding without removing the symptom.

## Root cause

The composer bar and the list are clocked one display frame apart for the same inset value: the plugin writes the keyboard's **current** position from the pan handler to both the native bar constraint and the engine inset (`KeyboardManager.swift:496-518, 543-557`), the bar's constraint change is Core-Animation-committed in the write turn and shown at vsync N, while the Flutter frame that consumes the same write is shown at N+1 because a rasterized frame only becomes a layer commit on a later main-thread turn (`FlutterMetalLayer.mm:398-444`); the keyboard moves between those frames, so the list edge lags by one frame of travel (20-55 pt at 60 Hz for a D ~ 330 pt keyboard, `docs/superpowers/specs/2026-11-10-hosted-bar-ownership-design.md:116`).

Causal chain, in order:

1. The interactive drag is tracked by the plugin's display link; each tick computes `barInset` from the keyboard-layout-guide delta and applies it to the bar constraint and to the engine in the same call (`KeyboardManager.swift:478-540, 543-557`).
2. The bar's `NSLayoutConstraint` change is committed by Core Animation at the end of that main-runloop turn, so it is presented at the next vsync N.
3. The engine inset write is a posted UI-runner task (`shell/common/shell.cc:1154-1160`; `fml/task_runner.cc:68-81` - it is a plain `PostTask` from the platform thread, not a blocking handoff); on the UI thread it marks the `RenderView` for layout and `MediaQuery` for rebuild (`rendering/binding.dart:399-413`, `widgets/media_query.dart:2388-2411`), and the body height is built from `viewInsets.bottom` (`material/scaffold.dart:3219-3230, 1085-1114`).
4. That framework frame is rasterized and only then committed to Core Animation on the main thread inside a `CATransaction` (`FlutterMetalLayer.mm:398-444`), so its pixels are presented one vsync after the bar's - it shows the keyboard position the write described, while the keyboard and bar have already moved to the next one.
5. The viewport clips at its own bounds (`rendering/viewport.dart:968-986`), so the stale edge is rendered as a hard cut across the message text with app background between it and the bar.
6. The engine's own notification-driven inset animation does not have this problem because it writes the value for the **next presentation time** on purpose: `projectedTargetTime = targetTime + frameInterval`, commented "Make sure the new viewport metrics get sent after the begin frame event has processed" (`FlutterKeyboardInsetManager.mm:393-403`). The plugin's drag writes are current samples with no such projection (`KeyboardManager.swift:441-468, 478-540`).

A second, smaller producer adds to the band near the ends of a transition: the bar's height changes by the home-indicator padding while the keyboard is at the bottom of the screen (`CIKHostedAccessoryBar.swift:60-77, 145-153`), and the Flutter reservation follows that height through a channel event animated by `TweenAnimationBuilder` (`lib/src/cupertino_hosted_input_accessory.dart:139-149, 186-198`), a different clock and curve from the native bar. An earlier device trace measured a 34 pt reservation step at the start of a close (`docs/superpowers/specs/2026-11-10-hosted-bar-ownership-design.md:112-124`).

The junction has no absorbing term. With the Scaffold body ending at the engine inset (list viewport bottom = S - viewInsets - R) and the native bar's top at S - i_native - barHeight, the visible band is

    gap = (viewInsets - i_native) + (R - barHeight)

(Scaffold body height: `material/scaffold.dart:1088-1114, 3220-3222`; viewport clip: `rendering/viewport.dart:969-985`; reservation: `lib/src/cupertino_hosted_input_accessory.dart:139-149`; derivation in `docs/research/notes/flutter-layout-clip.md`). The example's Column places the list and the reservation as siblings, so the gap has zero tolerance: any disagreement between the terms is painted as Scaffold background between the cut viewport edge and the bar. Three terms can produce the observed band and each has a different signature: (a) `viewInsets - i_native` is the one-frame transport hop and scales with drag speed (20-55 pt per frame at 60 Hz for a hard flick); (b) `R - barHeight` is the reservation against the native bar's animated height, a fixed step of at most 34 pt at padding flips only; (c) a constant drag-start seeding bias between `barInsetAtDragStart` and the first live guide reading (`KeyboardManager.swift:217-236, 492-506`), constant at every speed. A band that grows with a fast flick is (a); a band that is always the same size is (b) or (c).

## The test that would fail without the fix

**`fastDragKeepsTheListEdgeOnTheBarEdge`** - a trace assertion over a captured `CIKTrace` run: for every display-link tick during a fast drag, the bar's presented bottom (`hostedAccessoryBar.layer.presentation().frame.maxY`) and the list's rendered bottom edge (a `GlobalKey` render box logged from a `WidgetsBindingObserver.didChangeMetrics` twin) must agree within 0.5 pt. Today they differ by one frame of keyboard travel (20-55 pt at 60 Hz). It belongs with the existing host-runnable harness (`ios/KeyboardGeometryTests/run.sh`) as a new `ios/DragPacingTests/` target, because it needs a device trace, not a widget test.

A pure unit test can carry the fix's math in the same Swift harness: **`dragInsetIsProjectedOneFrameAhead`** in `ios/KeyboardGeometryTests/main.swift` - for guide samples 508 -> 508+40 -> 508+80, the value published to the engine must be the sample one frame ahead (clamped), while the value applied to the bar must stay the current sample.

App-side harness test for the seam-hiding half: **`theListViewportEdgeIsHiddenBehindTheComposer`** in `test/hosted_input_accessory_test.dart` - with the mocked channel, pump the screen with `viewInsets.bottom = 336` and emit `{'type': 'height', 'height': 98.5}`, then assert the ListView's bottom equals the accessory band's bottom within 0.5 pt (it fails today by about the bar height, because the list bottom is the band's top), the band is at least 96 pt tall, and the ListView's bottom padding is at least 98.5 pt.

No widget test can express the defect: the two edges live in different engines and one is a native view. That is why the trace assertion is the test, and why the confidence is lowered to medium until it is run.

## Hypotheses

| id | Hypothesis | Would be killed by |
|---|---|---|
| H1 | Leading: the list edge is one display frame behind the keyboard/bar edge because a Flutter frame presents one vsync after its build while a native constraint presents in the write turn, and the plugin writes current rather than projected values; the band therefore scales with drag speed. | A device trace in which the bar's presented bottom and the list's rendered bottom agree within 0.5 pt on every tick of a fast drag. |
| H2 | Rival, secondary: the band is a fixed mismatch, independent of drag speed - either the Flutter reserved bar height (channel event + `TweenAnimationBuilder`) against the native bar's real height (its own padding and `UIView.animate`), or the drag-start seeding of `barInsetAtDragStart` against the first live guide reading; it is visible at rest and at the ends of a transition. | A trace showing reserved height and native bar height equal (within 0.5 pt) and the drag-start seed matching the first live guide reading, while the band still appears in the middle of a fast drag. |
| H3 | Rival, untested: the list stutters because the per-frame `Scaffold` relayout plus DEBUG-mode frame cost drop frames, so the band is irregular rather than proportional to speed. | A frame-time trace (profile mode) with no missed frames during the drag. |
| H4 | Belief I think is wrong: the bar itself lags because its per-frame read of the engine inset is stale, so the composer detaches from the keyboard while the list is correct. | A frame showing the composer detached from the keyboard, or code showing the bar positioned by a display-link read of `physicalViewInsetBottom` (this tree does not have it). |
| H5 | Boring: there is no clock mismatch - the artefact is ordinary `ListView` viewport clipping and the reversed list's scroll offset, and the "band" is the composer's own background. | A frame showing the band wider than the composer's own padding, or a trace showing the edges disagreeing. |
| H6 | Belief I think is wrong: the second engine's / tracking link's unconfigured frame rate (60 Hz cap / no `preferredFrameRateRange`) is the cause. | A plist with `CADisableMinimumFrameDurationOnPhone` true, and frame-time data showing a 60 Hz device behaving identically to a 120 Hz one. |

Hypotheses considered and dropped: "UIKit's guide is stale so the bar lags" (same mechanism as H4, no distinct evidence); "the second engine's frame is late" (the bar is drawn by the second engine, but its *position* is a native constraint - the composer's pixels may trail, its container cannot).

## Evidence

| id | Type | Locator | Credibility | Relevance | What it would prove |
|---|---|---|---|---|---|
| E1 | engine source read | `FlutterKeyboardInsetManager.mm:393-403` (local engine checkout, Flutter 3.47.7) | high - primary engine source | high | The engine deliberately writes the inset after the begin frame and evaluates the animation one frame interval ahead; it assumes a write-to-layout latency of one frame, so a current-sample write is one frame behind the presentation. |
| E2 | engine source read | `FlutterMetalLayer.mm:398-444` | high for the code; medium for the exact vsync it lands on | high | A rasterized frame becomes a Core Animation layer commit on a later main-thread turn; a frame built at vsync N is shown at N+1, one vsync after a native constraint committed in the write turn. |
| E3 | repo source read | `KeyboardManager.swift:173-189, 232-234, 441-468, 478-540, 543-557` | high - the tree under study | high | The plugin writes the *current* sample to the bar constraint and to the engine in the same call; the bar and the list are given the same value but presented on different clocks. |
| E4 | engine + framework source read | `shell/common/shell.cc:1154-1160`; `fml/task_runner.cc:68-81`; `rendering/binding.dart:399-413`; `widgets/media_query.dart:2388-2411`; `material/scaffold.dart:3219-3230, 1085-1114` | high - primary sources | high | The platform->UI handoff is a non-blocking posted task and the framework consumes it in the next build; the loss is not inside the write path (it corrects the repo audit's "blocking handoff" reading). |
| E5 | external source | react-native-keyboard-controller PR #412, merged 2024-05-02 (https://github.com/kirillzyusko/react-native-keyboard-controller/pull/412, retrieved 2026-11-10) | high - merged production fix with documented failed alternatives | high | Reading layer geometry per display link is structurally one frame stale; the shipped fix is prediction of the upcoming frame, not a faster read. |
| E6 | prior device trace (repo doc) | `docs/superpowers/specs/2026-11-10-hosted-bar-ownership-design.md:112-124` | medium - single-observer DEBUG trace | high | Two producers were already measured disagreeing on device (inset 329.6 -> 0 and listH 299.8 -> 595.5 in one step; 34 pt reservation step). Confirms a second producer exists, not that it dominates this drag. |
| E7 | repo doc | `docs/superpowers/specs/2026-11-09-keyboard-accessory-sync-design.md:18-21` | medium - repo reasoning, no locator | medium | The plugin team already concluded a display-link-time write is one frame late and moved the write to touch time; the remaining half (present) was not addressed. |
| E8 | image (owner) | `IMG_7155.png` attachment, 2026-11-10, DEBUG build | medium - one frame, no timestamps | high | The composer is glued to the keyboard while the list is cut with a background band above it; the band is wider than the composer's own padding. Kills H4 (bar stale) and weakens H5 (pure clipping). |
| E9 | framework source read | `rendering/viewport.dart:968-986` | high - primary framework | medium | The cut line is the viewport clipping to its own bounds; it is the rendering mechanism of the artefact, not its cause. |
| E10 | repo source read | `CIKHostedAccessoryBar.swift:60-77, 145-153`; `KeyboardManager.swift:325-343`; `lib/src/cupertino_hosted_input_accessory.dart:139-149, 186-198` | high - the tree under study | medium | The bar's height and the Flutter reservation are a second, differently-clocked producer; this is H2's mechanism. |
| E11 | repo source read | `example/lib/keyboard_accessory.dart:155-175`; `example/ios/Runner/Info.plist:5-6` | high | medium | The repro screen uses Scaffold's resize (body height = viewInsets), and the plist already enables ProMotion 120 Hz, so a 60 Hz lock is not the explanation. |
| E12 | external issue | flutter/flutter#175790 (open, 2025-09-22; https://github.com/flutter/flutter/issues/175790, retrieved 2026-11-10) | medium - reporter-measured, ongoing | medium | Flutter shows multi-frame stimulus-to-display latency even at 120 Hz; a one-frame correction fixes the systematic offset, not all pipeline latency. |
| E13 | repo absence | no device trace exists for this report: no run was permitted, and the trace toggle only forwards lines to the Dart console (commit in progress, `lib/cupertino_interactive_keyboard.dart:6-15`) | high - the tree is the artefact | high | The decisive measurement has not been taken; the ranking is source-based. |
| E14 | derived geometry (source) | `gap = (viewInsets - i_native) + (R - barHeight)`; `material/scaffold.dart:1088-1114, 3220-3222`; `rendering/viewport.dart:969-985`; `lib/src/cupertino_hosted_input_accessory.dart:139-149`; derivation in `docs/research/notes/flutter-layout-clip.md` | medium-high - arithmetic from primary sources, not measured | high | The junction has zero tolerance: a visible band exists only when one of the three terms is non-zero, and its size is the term sum. |
| E15 | lane note (signature table) | `docs/research/notes/flutter-layout-clip.md` - three signatures: speed-proportional (transport hop), fixed <= 34 pt step at padding flips, constant (drag-start seeding) | medium - derivation, no per-frame trace | high | The three producers are separable by observing whether the band depends on drag speed; this is the cheapest discriminator available to the owner today. |
| E16 | external code read (consumer app) | consumer app already overscans the composer slot by `composerHeight/2` (reported in `docs/research/notes/flutter-layout-clip.md`) | medium - single read, no measurement | medium | A half-bar overscan can only hide a mismatch smaller than ~26-43 pt, so the artefact would appear exactly on fast flicks - independently of this plugin's example, matching the owner's report. |

Deleted rows: none; every row separates at least two hypotheses (checked in the matrix below).

## Matrix

| evidence | H1 timing | H2 arithmetic | H3 jank | H4 bar stale | H5 clipping only | H6 frame rate |
|---|---|---|---|---|---|---|
| E1 engine projects one frame ahead | C | NA | NA | NA | NA | NA |
| E2 present is a deferred CA commit | C | NA | NA | NA | NA | NA |
| E3 plugin writes current sample to both | C | NA | NA | I | NA | NA |
| E4 write path adds no frame | C | NA | NA | NA | NA | NA |
| E5 RN #412 one-frame stale read, fix predicts | C | NA | NA | C | NA | NA |
| E6 prior device trace: two producers, 34 pt step | NA | C | NA | NA | NA | NA |
| E7 repo: display-link write is one frame late | C | NA | NA | NA | NA | NA |
| E8 owner frame: composer glued, band wider than padding | C | C | NA | I | I | NA |
| E9 viewport clips at its bounds | C | NA | NA | NA | C | NA |
| E10 reservation vs native bar height, different clocks | NA | C | NA | NA | NA | NA |
| E11 plist enables 120 Hz | NA | NA | NA | NA | NA | I |
| E12 Flutter multi-frame latency at 120 Hz | C | NA | NA | NA | NA | I |
| E14 gap formula, zero-tolerance junction | C | C | NA | NA | I | NA |
| E15 three signatures (speed / step / constant) | C | C | NA | NA | I | NA |
| E16 consumer overscan of half a bar shows only on fast flicks | C | NA | NA | NA | NA | NA |

Ranking by contradictions (fewest first): H1 = 0, H2 = 0, H3 = 0, H5 = 3, H4 = 2, H6 = 2.

H4 and H6 are ruled out. H5 is reduced to the rendering mechanism (the cut line) rather than the cause of the band. H3 cannot be graded further: no frame-time data exists, so its zero contradictions mean "untested", not "likely" - and the matrix rules require saying so. H1 leads on support (E1, E2, E3, E4, E5, E7, E8: all consistent, four of them high-credibility primary sources), while H2 is a real but secondary producer (E6, E8, E10) whose 34 pt term cannot produce a 50-85 pt band in the middle of a fast drag. The tie between H1 and H2 on contradiction count is therefore not a tie on support; it is a tie that the trace resolves.

## Ruled out

- **H4 (the bar itself lags, the list is fine)** is contradicted by E3 and E8: the bar is positioned from the same `barInset` the engine is given (`KeyboardManager.swift:496-518`), there is no display-link read of `physicalViewInsetBottom` positioning the bar in this tree (checked across `ios/`), and the owner's frame shows the composer glued to the keyboard.
- **H6 (unconfigured frame rate / 60 Hz cap)** is contradicted by E11 (the example's `Info.plist` already sets `CADisableMinimumFrameDurationOnPhone` true) and E12 (multi-frame latency is measured at 120 Hz too). An unconfigured `preferredFrameRateRange` on the plugin link (`KeyboardManager.swift:232-234`) is a possible second-order factor, not the cause.
- **H3 (frame drops) is not ruled out, and the matrix must not be read as supporting it.** The layout lane found one relayout of the Scaffold body per frame and a Column whose widget identity skips the rebuild (`framework.dart:4027` as reported in `docs/research/notes/flutter-layout-clip.md`), but no frame-time data exists in this tree; H3's zero contradictions mean it was never tested, not that it is likely.
- **H5 (ordinary clipping with no mismatch)** is contradicted by E8, E14 and E15: the gap formula has no absorbing term, so a band can only exist when one of the three terms is non-zero; clipping is only the rendering mechanism of the cut line (E9). The owner's frame shows a band, not a flush edge.

## Fix direction

A fix has two separable halves, and the second must not be mistaken for the first.

**The lag half.** Give the engine a value that is correct at the presentation time of the frame that carries it: project the drag inset one frame ahead for the engine write, mirroring what the engine itself does for notifications (`FlutterKeyboardInsetManager.mm:393-403`) and what the merged RN #412 fix does, while the native bar keeps the current value. The projection factor (one or two frame intervals) has to be calibrated against the per-tick trace. This is the only change that removes the disagreement instead of hiding it.

**The seam half.** No static geometry can hide a list edge that is one frame higher than the native bar, because the Flutter reservation moves on the stale clock too (E14). The practical options are: (i) projection only, accepting a residual when frames are dropped; (ii) put both producers on one clock - delay the bar by one frame and give the bar's native view a bottom overscan and a background colour so it covers the keyboard gap while the composer trails by the same frame (deterministic, no prediction, but gives up the bar's 1:1); (iii) an app-side mitigation that turns the cut line and the background-coloured band into a same-colour band inside the composer's slot - the full-bleed overscan recipe in `docs/research/notes/flutter-layout-clip.md`: list viewport to the body bottom, bottom padding = reported bar height + 8, an opaque backing band of the same height, accessory reduced to a height reporter (the plugin must expose the total height it already computes). It does not remove the lag, it removes the visible cut and colour step, and it is cheap and reversible.

Order: the trace first (one device run in profile mode), then the projection calibrated by it; take (iii) at the same time if the screen has to look clean before the projection is validated; (ii) is the fallback if prediction proves jittery.

## Flip condition

**E2** is the critical item: if a device trace shows that a frame built at vsync N is presented at N (i.e. the bar's presented bottom and the list's rendered bottom agree within 0.5 pt on every tick while the plugin still writes current samples), the one-frame present offset does not exist, H1 collapses to H2 (reservation arithmetic) or H3 (frame drops), and the fix moves from clock projection to the reserved-height plumbing or the relayout cost - not to the inset writer. Conversely, a trace showing an offset equal to one frame of travel, shrinking when the write is projected one frame ahead, confirms H1 and the fix above.

## Addendum (same day, after implementation)

The projected-inset fix was implemented (`projectedInset`, one refresh of lead from the display-link velocity) and the band remained. That narrows the root cause further: the write-to-frame delay is not stable, because writes come from the pan handler, a deferred main-queue turn and a display-link tick, and which frame consumes each one depends on runloop ordering - over- and under-correction alternate. A constant lead is therefore not a fix, and the matrix's H1 must be read as "the two clocks are structural", not "one frame of offset". The projection was reverted; any further fix has to either stop driving the list per frame or put the composer and the list on one clock.

## Milestone

The first device run: debug with the per-tick trace on, because the trace is DEBUG-only (native `frame` line: `epoch`, refresh, lead, `physicalViewInsetBottom`, `barModel` and `barPresented` frame, `guideTop`; Dart `metrics` twin per `didChangeMetrics`: push counter, wall-clock ms, `schedulerPhase`, `viewInsets`), plus a profile run without the trace to judge pacing. If every tick shows the bar presented bottom and the list bottom agreeing within 0.5 pt, the timing hypothesis is dead and the ranking falls to the arithmetic producer. If the offset equals the per-frame travel and vanishes when the engine write is projected one frame ahead, H1 is confirmed.

## References

- react-native-keyboard-controller PR #412 - https://github.com/kirillzyusko/react-native-keyboard-controller/pull/412 (retrieved 2026-11-10; merged 2024-05-02)
- flutter/flutter#175790 - https://github.com/flutter/flutter/issues/175790 (retrieved 2026-11-10; open, 2025-09-22)
- flutter/flutter#150525 (merged platform/UI threads on iOS since 3.32) - https://github.com/flutter/flutter/issues/150525 (retrieved 2026-11-10)
- flutter/flutter#57609 (interactive dismissal never in the framework) - https://github.com/flutter/flutter/issues/57609 (retrieved 2026-11-10)
- Apple, `CADisableMinimumFrameDurationOnPhone` - https://developer.apple.com/documentation/bundleresources/information-property-list/cadisableminimumframedurationonphone (retrieved 2026-11-10)
- Local engine source: `/Users/vitekvitek/development/flutter/engine/src/flutter`, Flutter 3.47.7, engine revision `deb287481e`; framework: `/Users/vitekvitek/development/flutter/packages/flutter`.
- Supporting lane notes: `docs/research/notes/engine-inset-pipeline.md`, `docs/research/notes/prior-art.md` (2026-11-10).
