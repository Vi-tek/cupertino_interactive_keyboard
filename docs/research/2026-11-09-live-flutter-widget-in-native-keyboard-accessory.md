# Decision research: how to put a live Flutter widget into the native keyboard accessory view

- Lane: decision
- Date: 2026-11-09
- Decision: choose how the accessory bar is rendered so it moves 1:1 with the interactive iOS keyboard while staying a live Flutter widget (not an image, not a native bar), for the cupertino_interactive_keyboard plugin, under the constraints: iOS only, Flutter 3.47.7, no simulator/on-device verification available to the researcher, public API preserved if possible.
- Confidence: medium — the engine's one-view-controller-per-engine rule is primary-source evidence, but the runtime behaviour of a second engine's view inside the keyboard window is unverified (no device spike allowed).
- Written to: docs/research/2026-11-09-live-flutter-widget-in-native-keyboard-accessory.md

## Decision

The choice: how the bar that sits on top of the iOS keyboard is rendered, given the bar must be live Flutter widgets and must not trail the keyboard by even one frame.

Options in scope:
- **A. Second Flutter engine hosted in the accessory view.** A `FlutterEngine` from a `FlutterEngineGroup`, driven by a `FlutterViewController` whose view is added inside the plugin's `inputAccessoryView`. The accessory UI is built from a secondary Dart entrypoint (`@pragma('vm:entry-point')`), and mirrored state is pushed over a channel.
- **B. Same engine, second view (multi-view).** One Dart isolate renders the main app and the accessory into two views.
- **C. Status quo.** Widget in the main Flutter view, positioned by driving the engine viewport inset from the live band (shipped, commit e6406b8/0b0eac8).
- **D. Native UIKit accessory.** Real UIKit controls (previous/next/done) inside the inputAccessoryView.
- **E. Defer** until Flutter exposes iOS multi-view.

Deadline: none fixed; the plugin owner decides. Owner: the plugin author (cupertino_interactive_keyboard).

Doing nothing is option C: it costs one visible frame of bar lag and the owner has already rejected it on the device ("still some lag while dragging... recorrects... moves it a little down", and the bar trails when the keyboard opens). Deferring is option E: the same cost as C, plus the chance that Flutter ships multi-view.

## Criteria

| id | Criterion | Weight | Why it matters |
|---|---|---|---|
| C1 | Live Flutter widget content (no image, no native controls) | 0.35 | Owner's hard requirement: "i dont want image. it has to be a widget or something." |
| C2 | 1:1 motion on open, interactive drag and release | 0.30 | The original goal; a Flutter-drawn bar is composited a frame after UIKit's keyboard (this round of work proved it on device). |
| C3 | Integration cost and API surface (can `CupertinoInputAccessory(child: ...)` stay?) | 0.15 | A plugin that forces a second entrypoint is a different plugin; the owner pays that cost. |
| C4 | State and interaction fidelity (text editing, focus, IME) | 0.10 | The bar contains a TextField; a second isolate must not fork its editing state. |
| C5 | Maintenance and engine risk (public vs private API) | 0.10 | The plugin already leans on private engine selectors; more of that is a real cost. |

Criteria considered and dropped: "Android parity" (plugin is iOS-only by design, README:5); "battery/CPU" (the bar is on screen only with the keyboard; all options are comparable); "store policy" (nothing here is review-sensitive, both A and D use supported APIs).

## Comparison

| Option | C1 (0.35) | C2 (0.30) | C3 (0.15) | C4 (0.10) | C5 (0.10) | Weighted |
|---|---|---|---|---|---|---|
| A second engine | pass 0.35 | pass 0.30 | ~0.06 (new entrypoint API) | ~0.06 (display-only mirror) | 0.08 | **0.85** |
| B same-engine multi-view | pass 0.35 | pass 0.30 | 0.15 (API unchanged) | 0.10 | 0.02 (private engine API) | unavailable today — see below |
| C status quo | pass 0.35 | fail 0 (measured lag) | 0.15 | 0.10 | 0.10 | 0.70 |
| D native UIKit bar | fail 0 | 0.30 | 0.15 | n/a 0.05 | 0.10 | 0.60 |
| E defer | pass 0.35 | fail 0 | 0.15 | 0.10 | 0.10 | 0.70 (today), unknown later |

The criterion the decision is actually sensitive to is **C3**: if the owner refuses a new entrypoint/API, A drops below D (native bar), which is the only option that reaches C2 without an API change. The comparison is not sensitive to C4/C5 — they reorder nothing.

## Cost and effort

- A: a second `FlutterEngine` costs ~180 kB incremental and shares GPU context, font metrics and the isolate-group snapshot (docs.flutter.dev, "Multiple Flutter screens or views", retrieved 2026-11-09); a secondary entrypoint, a channel protocol for mirror state, accessory VC containment, show/hide swap logic. Estimate: 2–4 days of work, plus a new public API.
- C: sunk.
- D: a UIKit bar has to re-implement the app's bar (Field/buttons) natively — not the plugin's business.
- Source/date: effort figures are the researcher's estimate (2026-11-09), not measured.

## Reversibility

- A is additive: a new render path behind the existing widget; undoing it means deleting the second engine and the swap logic, no data risk, ~1 day.
- D is a permanent visual/UX change for every consumer of the plugin and hard to undo once released.
- C is free to keep and free to leave.

## Hypotheses

| id | Hypothesis | Would be killed by |
|---|---|---|
| H1 | A live Flutter widget can only ride the keyboard inside the native accessory view by hosting a second Flutter engine (from a `FlutterEngineGroup`) with its own Dart entrypoint; the accessory UI is a mirror built in that isolate. | A public same-engine multi-view API on iOS, or a supported way to attach a second `FlutterView` to an existing engine. |
| H2 | One engine can render the accessory into a second view (multi-view), keeping one isolate and the existing `child:` API. | The iOS embedder exposing only one `FlutterViewController` per engine and no public view-adding API. |
| H3 | The current inset-driven widget can be made visually 1:1 without hosting it in the accessory view. | A device observation of a persistent gap/lag (the owner reports exactly that), or the compositing argument that Flutter frames trail UIKit by one frame. |
| H4 | A native UIKit accessory is the only way to get 1:1 motion. | A working live-widget host (H1) — or the owner accepting a non-Flutter bar. |

## Evidence

| id | Type | Locator | Credibility | Relevance | What it would prove |
|---|---|---|---|---|---|
| E1 | file read | `Flutter.framework/Headers/FlutterEngine.h:36-37` — "may have zero or one FlutterViewController at a time" | high (primary header) | high | one engine cannot own two VCs → kills H2's simplest form |
| E2 | file read | `FlutterEngine.h:319-327` — "A FlutterEngine can only have one FlutterViewController at a time... will replace" | high | high | attaching a second VC detaches the app's view → H2 not possible |
| E3 | file read | Headers dir listing: no FlutterView header; `FlutterViewController.h:54-70` has no view-adding API | high | high | no public API to add a second view to an engine on iOS |
| E4 | binary symbol | `nm Flutter.framework/Flutter`: `t _FlutterEngineAddView` @0x563ddc, `t _FlutterEngineRemoveView`; `Shell::OnPlatformViewAddView`; Dart SDK `platform_dispatcher.dart:288 _addView` (private) | medium (internal API exists, not public) | high | multi-view machinery exists internally but is not exposed → H2 unavailable today, plausible tomorrow |
| E5 | file read | `FlutterEngineGroup.h:97-115` — `makeEngineWithEntrypoint:libraryURI:` | high | high | a second engine with its own Dart entrypoint is a supported public API |
| E6 | document | https://docs.flutter.dev/add-to-app/multiple-flutters (retrieved 2026-11-09): ~180 kB incremental, shared GPU context/font metrics/isolate-group snapshot, communication over platform channels | high (official docs) | high | H1 is feasible and cheaper than a full engine |
| E7 | file read | `ios/.../FlutterTextInputView+Swizzle.swift:35-50` — the plugin already installs any `UIView` (`plugin.inputView`) as `inputAccessoryView` | high | medium | hosting a VC's view inside the accessory is structurally possible |
| E8 | framework source read | `flutter/lib/src/widgets/view.dart:75` (`View` widget), `sky_engine/lib/ui/platform_dispatcher.dart:195` (`views`), `:288` (`_addView`) | high | high | a view needs its own widget tree rooted at that view; the app's `child` is built in the main tree → any second view needs a separate tree/entrypoint, so the `child:` API cannot survive unchanged |
| E9 | document | https://developer.apple.com/documentation/uikit/uiviewcontroller (view controller containment), retrieved 2026-11-09 | high | medium | a child VC's view can be added to any view, including the accessory view |
| E10 | interview / device observation | Owner report 2026-11-09: "still some lag while dragging... recorrects the position of the accessory, and moves it a little down"; "when opening the keyboard... it lags behind"; plus the analyst's read of the frame pipeline (Flutter composites after UIKit) | medium (one observer, but the owner) | high | H3 fails: the inset-driven widget is not 1:1 |
| E11 | source page | https://pub.dev/packages/native_keyboard_accessory (published ~2026-09, retrieved 2026-11-09): native inputAccessoryView bar "animates with it frame-for-frame ... cannot tear or lag behind the way a Positioned widget driven by view insets does" | medium (third-party package claim) | high | D works; H3 fails; also confirms the market uses native bars when 1:1 matters |
| E12 | source page | https://pub.dev/packages/overlay_keeb (retrieved 2026-11-09): Flutter widget content in a native overlay "defined within the plugin's secondary Dart entrypoint", `@pragma('vm:entry-point')` entrypoint; Android only | medium (third-party, single account, Android-only) | high | H1's secondary-entrypoint pattern is established prior art; iOS unproven |
| E13 | source page | https://api.github.com/repos/flutter/flutter/issues/124784 (retrieved 2026-11-09; opened 2023-04-13, open, 7 comments) — framework-level inputAccessoryView support request | high (primary issue tracker) | medium | no built-in Flutter widget-in-accessory support exists |
| E14 | file read | `ios/.../CIKInputAccessoryView.swift:1-43` — the band is a plain `UIView` with a height constraint and `hitTest` returning nil | high | low | the band can host any subview (deleted from the matrix: reads the same under H1, H2 and D) |

## Matrix

| evidence | H1 second engine | H2 same-engine multi-view | H3 status quo 1:1 | H4 native bar |
|---|---|---|---|---|
| E1 one VC per engine | C | I | NA | NA |
| E2 one VC at a time | C | I | NA | NA |
| E3 no public view API | NA | I | NA | NA |
| E4 internal AddView only | NA | I | NA | NA |
| E5 EngineGroup entrypoint | C | NA | NA | NA |
| E6 EngineGroup cost/sharing | C | NA | NA | NA |
| E8 view ⇒ own widget tree | C | I (API cannot stay) | NA | NA |
| E9 VC containment | C | C | NA | NA |
| E10 device lag report | NA | NA | I | NA |
| E11 native bar frame-for-frame | NA | NA | I | C |
| E12 secondary entrypoint prior art | C | NA | NA | NA |
| E13 framework issue open | NA | I | NA | NA |

Deleted rows: E7 (deleted from ranking — reads C for every option, no diagnostic value; the fact it establishes is that a view host exists, which is already assumed by all options). E14 was never admitted: also non-diagnostic.

Ranking by contradictions (fewest first): H1 = 0, H4 = 0, H3 = 2, H2 = 6.

H1 has no contradicting row in this version: the evidence that would kill it (a public second-view API on an existing engine, or an iOS multi-view exposure) is absent — E3/E4 show only internal, non-public machinery. Its support is therefore real but thin (E5, E6, E9, E12), which the confidence level reflects.

H4 ties H1 on contradictions; the tie is broken by the decision criteria, not by evidence: H4 fails C1 (live widgets), which the owner stated as a hard requirement.

## Ruled out

- **H2 (same engine multi-view)** — killed by E1, E2, E3, E4, E8, E13: one `FlutterViewController` per engine, no public per-view API, and a second view would still need its own widget tree, so the `child:` API could not stay anyway.
- **H3 (status quo is 1:1)** — killed by E10 (owner's on-device report) and E11 (third-party native bar documents the overlay lag it avoids).
- **H4 (native bar)** — survives evidence, loses on criterion C1; it is the fallback if the owner ever relaxes "must be a widget".

## Recommendation

**Build A: a second Flutter engine (from a `FlutterEngineGroup`) and a `FlutterViewController` whose view is placed inside the plugin's `inputAccessoryView`, with the accessory UI built from a secondary Dart entrypoint and mirror state pushed over a channel.**

Why: it is the only option that satisfies both hard requirements (live Flutter widgets, 1:1 motion), it uses only public Apple/Flutter APIs (EngineGroup, view controller containment), and the engine cost is documented as small (~180 kB incremental, shared GPU/font/snapshot resources). H2 would be better but is not available in this Flutter version.

Minimal reversible first step: prototype the accessory host behind a new opt-in API (e.g. `CupertinoInputAccessory.native(entrypoint: ...)`) and keep the current inset-driven bar as the default; the render path can be removed without touching the existing API.

Design constraints the report fixes for the next step:
- The mirrored bar is display-only while the keyboard moves; at rest the main Flutter bar stays interactive, so the TextEditingController is never forked (C4).
- The accessory engine should be created lazily and kept for the app's lifetime; a `FlutterEngineGroup` shares resources (E6).
- The swap is paint-only (hide the main bar with opacity, show the hosted view) so it cannot relayout the app.

## Counter-evidence to the recommendation

E12 is the closest thing to evidence against H1: the secondary-entrypoint pattern is only demonstrated on Android (`overlay_keeb`), so rendering a second engine's view inside the iOS keyboard window is unproven, and the keyboard window (`UITextEffectsWindow`) is a window the app does not normally own. That is why confidence is medium rather than high.

## Flip condition

The single piece of evidence that would change the recommendation: a **public, supported way to attach a second `FlutterView` to an existing engine on iOS in this Flutter version** (e.g. `FlutterEngine` gaining an `addView`/`removeView` API in the headers, or the multi-view `FlutterEngineAddView` symbol surfacing in a public header). If that appears, H2 wins: it keeps one isolate and could preserve the `child:` API (the widget tree question would still have to be settled, but no second isolate and no channel mirror). Without it, A stays the only live-widget 1:1 option.

## Milestone

The dated observation that confirms or overturns: the first on-device run of the opt-in accessory host, showing (a) the hosted bar's bottom edge stays on the keyboard top through open, drag and release, and (b) the hosted bar renders Flutter widgets (text, cursor, icons) correctly inside the keyboard window. If the hosted view does not render or does not move with the keyboard, the recommendation falls back to D (native bar) or C (accept the frame).