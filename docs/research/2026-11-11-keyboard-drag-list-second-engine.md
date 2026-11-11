# Coding research: the chat list trails the interactively dismissed keyboard, and a second Flutter engine would not fix it

- Lane: coding
- Date: 2026-11-11
- Decision: Choose how the chat list follows an interactively dismissed iOS keyboard when the screen moves to `resizeToAvoidBottomInset: true` (second engine vs one-engine overscan vs keeping `resizeToAvoidBottomInset: false`), for the plugin owner, under the constraints that the composer stays a Flutter widget in the second engine, the list stays the app's real Flutter list (chat state, overlays, navigation, a11y, one isolate), and the interactive dismissal keeps its current feel.
- Confidence: high that the second-engine attribution and the `resizeToAvoidBottomInset` switch are both the wrong lever; medium that the visible trail is exactly one refresh of keyboard travel rather than jank or a two-refresh lag - no device trace of a drag exists in either repo.
- Written to: docs/research/2026-11-11-keyboard-drag-list-second-engine.md
- Continues: `docs/research/2026-11-10-keyboard-drag-list-lag.md` (deleted from HEAD in eb5aa9f; recover with `git show eb5aa9f^:docs/research/2026-11-10-keyboard-drag-list-lag.md`), whose projection addendum is evidence E11 here.

## Symptom

On the iOS chat screen the hosted Flutter composer bar rides the keyboard frame for frame, while the message list visibly stops tracking during an interactive keyboard drag: the newest message and the list's bottom edge trail the composer/keyboard by a distance that grows with drag speed, and with the composer in a `Column` slot the same mismatch opens a background band between the list's clipped bottom edge and the composer's top edge. Observed by the owner on device (report of 2026-11-11 and the 2026-11-10 frame in the earlier report), not by this researcher.

Reproduction status: **not reproduced here** - no device or simulator run was performed in this pass. What was tried: reading the plugin's native positioner and inset writer (`ios/.../KeyboardManager.swift`, `CIKHostedAccessoryBar.swift`), the engine's inset and presentation source at the pinned revision (framework `abaf9c5237`, engine `deb287481e`), the framework resize path, and the consumer app's chat layout; plus two independent evidence passes (engine-source verification and second-engine/prior-art evaluation). The measurement that would reproduce it - a per-frame `CIKTrace` of one drag - does not exist in either repo.

## Root cause

The list is moved by a Flutter frame laid out from the last inset sample, and such a frame cannot be presented until one refresh after UIKit has already moved the keyboard and the native bar; the bar is exempt only because its pixels are static and its container is positioned by UIKit in the current Core Animation transaction (`KeyboardManager.swift:481-557`, `FlutterKeyboardInsetManager.mm:396-403`, `rasterizer.cc:683-686`, `CIKHostedAccessoryBar.swift:97-112`).

Causal chain, in order, with a locator per link:

1. During an interactive dismissal UIKit moves the keyboard; the plugin reads the live keyboard position from the layout guide's delta and, in the same call, moves the bar's bottom `NSLayoutConstraint` and writes the live inset into the main engine (`KeyboardManager.swift:481-557`; bar constraint `CIKHostedAccessoryBar.swift:97-112`).
2. The bar's constraint change is committed by Core Animation at the end of that main-runloop turn, so the bar is presented at the next refresh (`CIKHostedAccessoryBar.swift:97-112`; `KeyboardManager.swift:551-557` calls `layoutIfNeeded` so the model frame is current before the commit).
3. The engine write is synchronous into the engine's viewport metrics: iOS merges the platform and UI threads and `shell.cc` runs the UI work inline (`FlutterDartProject.mm:68`, `settings.h:385-386`, `FlutterEngine.mm:927-939`, `shell.cc:1154-1160`, `platform_configuration.cc:199-228`). This does **not** buy a frame: the framework only schedules a frame for the next vsync (`rendering/binding.dart:404-413`, `animator.cc:250-269`).
4. That frame carries `presentation_time` = the next vsync's target, i.e. it is scheduled for the refresh after the one in which it was built (`rasterizer.cc:683-686`, `flow/surface_frame.h:85-87`), and its rasterized contents become a Core Animation commit on a later main-thread turn (`FlutterMetalLayer.mm:398-423`). Content laid out from the inset sample therefore appears one refresh after the keyboard occupied that position; a write made mid-gesture can reach at best the frame built this vsync, so the on-screen content is up to two refreshes behind the touch.
5. The framework is built on exactly this assumption: the engine's own keyboard inset animation projects the value one frame interval ahead before writing it, with the comment "Make sure the new viewport metrics get sent after the begin frame event has processed" (`FlutterKeyboardInsetManager.mm:393-403`). The plugin writes **current** samples instead (`KeyboardManager.swift:481-557`, `publishInset` at :603-616), from three differently-timed places (pan handler, deferred main-queue turn, display-link tick), which is why the one-frame lead attempted on 2026-11-10 over- and under-corrected and was reverted (E11).
6. The framework places the Scaffold body at `screen - appBar - viewInsets.bottom` when `resizeToAvoidBottomInset` is true (`scaffold.dart:1090`, `:3222`) and the viewport clips at its own moving bottom edge with `Clip.hardEdge` (`rendering/viewport.dart:968-986`). With the composer in a `Column` slot, that late edge is exactly the bar's top edge at rest, so the mismatch is exposed as a cut row and a background band rather than absorbed.

## The test that would fail without the fix

The layout half has a runnable widget test: **`listBleedsBehindTheComposerBandAndItsContentClearsIt`** in `test/hosted_input_accessory_test.dart` (pattern of the existing mock, `test/mock_cupertino_interactive_keyboard.dart`). Pump the chat screen at iOS with `resizeToAvoidBottomInset: true`, `viewInsets.bottom = 336` and a reported total bar height of 98.5; then assert (a) the `ListView` viewport's bottom equals the opaque backing band's bottom (it fails today by the reserved bar height, because the list ends at the band's top), (b) the list's bottom padding is at least the reported bar height + the rest gap, and (c) the backing band is at least one bar height tall. This is the test the fix must leave green; it cannot express the frame trail, because the two moving surfaces live in different render paths (one Flutter frame, one UIKit constraint).

The frame half has no widget test. It needs a trace assertion: **`everyDragTickKeepsTheListEdgeOnTheBarEdge`** in a device harness (a `debugPrint`-fed assertion over one `CIKTrace` run: for every tick, the bar's presented bottom and the list's rendered bottom agree within 0.5 pt). Today they differ by one refresh of keyboard travel. Its absence is why the confidence above is medium and not high.

## Hypotheses

| id | Hypothesis | Would be killed by |
|---|---|---|
| H1 | Leading: the list's content and clip edge are one refresh (up to two from the touch) behind because Flutter cannot present a frame built from UIKit's live keyboard motion in the same refresh, and the plugin writes current rather than projected samples. | A device trace in which the bar's presented bottom and the list's rendered bottom agree within 0.5 pt on every tick of a fast drag. |
| H2 | Belief I think is wrong: the accessory is glued because it runs in a second Flutter engine, so moving the list into a second engine would glue the list too; therefore the list should be hosted in an engine. | Code showing the bar's position is a native constraint on a fixed-size Flutter layer, the engine being blind to it; and a traced fixed-pipeline answer showing a resized second engine repeats the same one-refresh lag. |
| H3 | Boring: the trail is debug-mode jank - the per-frame relayout plus the second engine's cost drop frames, so the motion is irregular rather than a constant lag. | A profile-mode frame-time trace showing no missed frames during a drag while the lag persists; or the opposite trace, which would demote H1. |
| H4 | Rival: `resizeToAvoidBottomInset: false` + manual bottom padding is itself the cause, and the framework's own resize would be frame-synchronised because Scaffold is "closer to the engine". | The framework's resize is driven by the same `MediaQuery.viewInsets` value delivered through the same metrics write; no second, more synchronous path exists. |
| H5 | Rival, secondary: what the owner sees as "lag" is not the content motion but the exposed moving clip edge / background band of the zero-tolerance `Column` seam, i.e. the list appears to stop because its bottom is cut before the composer. | A frame or trace showing the band is absent while the trail remains, or present while the content edge is aligned. |
| H6 | Rival: the plugin's write is merely late relative to the engine's vsync, so projecting the write one frame ahead would fix it without moving any architecture. | The 2026-11-10 addendum: projection was implemented from display-link velocity and reverted because the write timing is unstable and the correction alternated. |

## Evidence

| id | Type | Locator | Credibility | Relevance | What it would prove |
|---|---|---|---|---|---|
| E1 | engine source read | `FlutterKeyboardInsetManager.mm:393-403` (framework 3.47.7 / engine `deb287481e`) | high - primary engine source plus a test asserting the serialization (`FlutterViewControllerTest.mm:681-721`) | high | The engine itself assumes a one-frame write-to-layer latency and projects the inset one frame interval ahead; a current-sample write is therefore behind by construction. Supports H1, undercuts H6 as "write sooner". |
| E2 | engine source read | `rasterizer.cc:677-687`; `flow/surface_frame.h:85-87` | high - primary engine source | high | A frame built at vsync N carries `presentation_time` = the N+1 refresh and cannot appear at N. Flutter-drawn content cannot be pixel-synchronous with a UIKit constraint. Supports H1. |
| E3 | engine source read | `FlutterDartProject.mm:68`; `settings.h:385-386`; `FlutterEngine.mm:927-939`; `shell.cc:1154-1160`; `platform_configuration.cc:199-228`; `rendering/binding.dart:404-413`; `animator.cc:250-269` | high - primary sources | high | iOS merges platform and UI threads and the write reaches Dart synchronously, yet frame production is vsync-gated. Rules out "add a faster hop" and H4's premise. |
| E4 | repo source read | `KeyboardManager.swift:202-218, 481-557, 603-616` | high - the tree under study | high | The plugin writes current samples from three differently-timed producers; this is the mechanism H1 names and why the projected attempt of 2026-11-10 could not hold a lead. |
| E5 | repo source read | `CIKHostedAccessoryBar.swift:97-112, 121-132`; `KeyboardManager.swift:551-557`; `CupertinoInteractiveKeyboardPlugin.swift:277-291` | high - the tree under study | high | The bar's position is a native constraint on a fixed-size transparent Flutter layer; the second engine's frame pipeline is not involved in where the bar is drawn. Kills H2's causal claim. |
| E6 | engine source read | `FlutterViewController.mm:1377-1391, 1508-1522`; `FlutterMetalLayer.mm:398-423`; `ios_surface_metal_impeller.mm:54-58` | high for the pipeline; medium for the exact present instant | high | A second engine in a host view that resizes reads new bounds only at layout and repeats metrics -> layout -> raster -> CA, one refresh later. Kills H2 as a fix. |
| E7 | engine source read | no transform read outside platform views; metrics from bounds/safeAreaInsets (`FlutterViewController.mm:1508-1538`); `media_query.dart:300-309` | high that the engine is blind; medium-inferred for the consequences | medium | The only frame-perfect route is a natively translated, fixed-layout engine surface - which leaves `MediaQuery`, scroll extent, IME and a11y computing against the un-keyboarded height. Explains what the "list in an engine" idea would really cost. |
| E8 | framework source read | `scaffold.dart:1090, 3222`; `media_query.dart:309`; `rendering/binding.dart:404-413`; body inset removal `scaffold.dart:3034` | high - exact SDK checkout | high | `resizeToAvoidBottomInset: true` reads the same late `viewInsets` and lays the body out from it; it is not more frame-synchronised than manual padding, and inside the body `viewInsets.bottom` reads 0. Kills H4. |
| E9 | framework source read | `rendering/viewport.dart:968-986` | high | high | The cut line and band are the viewport clipping at its own moving box edge: the rendering mechanism of the visible artefact (H5). |
| E10 | repo trace (recovered doc) | `docs/superpowers/specs/2026-11-10-hosted-bar-ownership-design.md:112-128` (in `eb5aa9f^`) | medium - single-observer DEBUG trace | medium | Measured two producers disagreeing on device (a 34 pt reserved-height step; a one-frame inset write on instant hide) - a real second producer exists, bounded to transition boundaries. Supports H5's secondary mechanism. |
| E11 | repo doc + diff | 2026-11-10 report addendum (`eb5aa9f^:docs/research/2026-11-10-keyboard-drag-list-lag.md`) | medium - own project record, no trace | high | Projecting the engine write one frame ahead was implemented and reverted: over- and under-correction alternated because write scheduling is unstable. Kills H6 as a simple fix. |
| E12 | repo source read (consumer app) | `../uptalk/lib/view/chat/presentation/direct_chat_page_body.dart:203, 1498-1572`; `direct_chat_page_state.dart:212-301, 919-957`; `direct_chat_page_scaffold.dart:72-78`; `bottom_overlap_viewport.dart:1-76` | medium-high - app repo, may drift from the shipping build | medium | The real app already uses the one-engine, no-moving-edge design (`resizeToAvoidBottomInset: false` + carried padding + overscan + opaque composer). Switching it to `resizeToAvoidBottomInset: true` inverts that design rather than improving it. |
| E13 | external source | RN keyboard-controller interactive-keyboard docs and PR #1047 (https://kirillzyusko.github.io/react-native-keyboard-controller/docs/guides/interactive-keyboard , https://github.com/kirillzyusko/react-native-keyboard-controller/pull/1047, accessed 2026-11-11); flutter/flutter#57609 (https://github.com/flutter/flutter/issues/57609) | high that shipped fixes use native per-frame tracking/prediction; medium on version specifics | high | Every shipped solution to this seam keeps the content in one render surface and fixes the *position source* natively or by prediction; none hosts a scrollable list in a second engine. Kills H2 as prior art. |
| E14 | repo absence | no `CIKTrace` drag capture exists in `cupertino_interactive_keyboard` or `../uptalk` (search of both trees, 2026-11-11) | high - the tree is the artefact | high | The decisive per-frame measurement has not been taken; H1, H3 and the magnitude of H5 are untested on hardware. |

## Matrix

| evidence | H1 clock | H2 second engine | H3 jank | H4 resize-false cause | H5 exposed edge | H6 projection fix |
|---|---|---|---|---|---|---|
| E1 engine projects a frame ahead | C | NA | NA | NA | NA | C (supports projecting for notifications) |
| E2 frames present one refresh later | C | I | NA | I | NA | NA |
| E3 merged threads, write synchronous, frame vsync-gated | C | NA | NA | I | NA | C |
| E4 plugin writes current samples from three producers | C | NA | NA | NA | NA | C |
| E5 bar position is a native constraint on a static layer | NA | I | NA | NA | NA | NA |
| E6 resized second engine repeats the pipeline | NA | I | NA | NA | NA | NA |
| E7 native translation leaves Flutter layout stale | NA | I (as a fix) | NA | NA | NA | NA |
| E8 resize reads the same late inset | NA | NA | NA | I | NA | NA |
| E9 viewport clips at its moving edge | C | NA | NA | NA | C | NA |
| E10 two producers measured disagreeing | NA | NA | NA | NA | C | NA |
| E11 projection attempted and reverted | C | NA | NA | NA | NA | I |
| E12 real app already uses the no-moving-edge design | NA | I (as a fix) | NA | C | C | NA |
| E13 prior art fixes the position source, not the engine | NA | I | NA | NA | NA | C |
| E14 no device trace exists | NA | NA | NA | NA | NA | NA |

Ranking by fewest contradictions: H1 = 0, H5 = 0, H3 = 0, H6 = 1, H4 = 2, H2 = 5.

H2 is ruled out as both a causal claim and a fix. H4 is ruled out as a cause: the resize path consumes the same late value, so switching the flag cannot change the frame ordering. H6 is ruled out as a simple fix: the engine's projection is exactly right for an animation it samples itself, but the plugin's write scheduling is unstable (three producers), which is why the earlier attempt alternated. H3 cannot be graded further - no frame-time data exists, so its zero contradictions mean **untested, not likely**; H1 and H5 both survive with zero contradictions, and they are co-producers of what the owner sees (H1 = the motion trail, H5 = the clipped edge/band), not rivals. H1 leads on support: E1-E4, E9, E11, E13 are all consistent, four of them primary engine/framework sources.

## Ruled out

- **H2 (the accessory is glued by the second engine, so a second engine would glue the list)** is contradicted by E5 and E6: the bar's bottom is an `NSLayoutConstraint` mutated each tick and laid out before the Core Animation commit (`KeyboardManager.swift:551-557`), while its Flutter layer is fixed-size and transparent, so the engine cannot be contributing to its position (`CIKHostedAccessoryBar.swift:121-132`). The engine group makes the second engine cheap, not synchronous. E7 shows the only frame-perfect variant is a natively translated fixed-layout surface, which then has stale `MediaQuery`/scroll/IME/a11y - and E12/E13 show the real app and every shipped prior-art fix avoid it: the list must reflow, scroll and interact, so its pixels change and cannot be moved as a cached layer.
- **H4 (resize:false + padding is the cause; Scaffold's resize would be synchronised)** is contradicted by E8 and E3: the Scaffold body is laid out from the same `MediaQuery.viewInsets` value delivered by the same metrics write, and the framework has no second, more synchronous path (`rendering/binding.dart:404-413`); inside the resize body the inset even reads 0. The flag changes which edge moves, not when.
- **H6 (projection alone fixes it)** is contradicted by E11: the projection was implemented from the tracking link's velocity and reverted because over- and under-correction alternated; the engine can project reliably only because it owns the write timing (E1), while the plugin's writes come from a pan handler, a deferred main-queue turn and a display-link tick (E4).
- **H3 (jank) is not ruled out** - no frame-time data exists in either tree (E14). Its zero contradictions mean untested, not supported; a profile-mode run would settle it.
- **H5 is reduced** to a contributor, not a rival: the band is the rendering of the mismatch (E9, E10), and on `resizeToAvoidBottomInset: false` with full-height list padding it disappears by construction (E12) - which is why the current app already uses that shape.

## Fix direction

**Do not build a second engine around the list.** Keep one engine and stop exposing the moving edge: with `resizeToAvoidBottomInset: true`, move the composer out of the `Column` into a bottom overlay, let the list reach the true body bottom (bleed behind the composer) with its content padded by the reported total bar height plus the rest gap, and paint an opaque band one bar height tall between the two (the 2026-11-10 "5.1" recipe). The plugin's only addition is exposing the total height it already computes as a listenable so the list and the band can follow a growing multiline composer. This removes the cut row and the background band; it does **not** remove the one-refresh content trail, which is structural (E1-E3) and appears as a small background gap between the newest message and the composer on a fast dismissal. If that trail itself is unacceptable, the only frame-perfect route is moving the whole chat surface (list + band + composer) into a native-translated hosted surface - a rewrite that gives up Flutter's overlays, navigation, scroll state and a11y for the screen (E7, E12).

## Flip condition

**E14 filled: one device trace from the shipped probe** (`setKeyboardTraceEnabled(true)`, native `[CIKTrace] frame`/`inset` lines at `KeyboardManager.swift:587-616` plus the Dart `metrics` line at `lib/cupertino_interactive_keyboard.dart:57-72`) taken during a fast drag in both directions. If it shows the bar's presented bottom and the list's rendered bottom agreeing within 0.5 pt on every tick, H1 collapses, the one-engine clock story is dead, and the ranking falls to H5 (reservation arithmetic / exposed edge) or H3 (jank) - with the fix moving to the reservation plumbing or frame cost, not to the inset writer or the architecture. If it shows a lag equal to one refresh of travel while the bar stays glued, H1 is confirmed and the layout fix above is the remaining lever unless the hosted-surface rewrite is chosen.

## Milestone

**One device run, profile mode where possible, 2026-11-11 or 2026-11-12**: enable the trace in the example, drag the keyboard fast down and fast up for 2-3 seconds, capture the per-tick `frame` line (bar model/presented frame, `physicalViewInsetBottom`, guide top), the `inset` line (the value the plugin wrote) and the Dart `metrics` line (push counter, `schedulerPhase`, `viewInsets`), then repeat without the trace in profile mode to judge pacing. Read the offset between the bar's presented bottom and the list's rendered bottom as a fraction of one refresh of keyboard travel; that number decides between H1 (layout fix, accept the trail), H5 (reservation/edge fix) and H3 (frame cost).

## References

- Prior report and addendum, deleted from HEAD in `eb5aa9f`: `git show eb5aa9f^:docs/research/2026-11-10-keyboard-drag-list-lag.md`; supporting notes `git show eb5aa9f^:docs/research/notes/engine-inset-pipeline.md`, `.../flutter-layout-clip.md`, `.../prior-art.md`.
- Framework source: `/Users/vitekvitek/development/flutter/packages/flutter/lib/src` at `abaf9c5237` (Flutter 3.47.7).
- Engine source: `/Users/vitekvitek/development/flutter/engine/src/flutter` at `deb287481e`.
- Consumer app read-only: `/Users/vitekvitek/development/uptalk` (chat screen, 2026-11-11).
- External: react-native-keyboard-controller interactive-keyboard docs and PR #1047 (accessed 2026-11-11); flutter/flutter#57609 (accessed 2026-11-11); Flutter embedder `FlutterKeyboardInsetManager` docs (accessed 2026-11-11).
