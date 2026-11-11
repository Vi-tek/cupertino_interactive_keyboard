# Design Doc: a hosted keyboard surface — the chat content moves with the keyboard, natively

- Date: 2026-11-11
- Status: proposed, awaiting owner approval
- Research: `docs/research/2026-11-11-keyboard-drag-list-second-engine.md`
- Context: the owner's requirement is "the lag gone" - not smaller, gone. The 2026-11-11 research shows a Flutter-rendered list cannot follow an interactively dismissed iOS keyboard frame for frame (the engine presents a frame one refresh after the UIKit motion it was laid out from), while the hosted accessory bar can, because its container is positioned by UIKit and its Flutter surface only holds cached pixels. This design applies that mechanism to the whole chat content area.

## Intent & The Why

The plugin already renders the composer in a second engine inside a native container that UIKit moves frame for frame. The list is the only remaining piece on the slow clock, and it is the piece the owner says must stop lagging. The fix is not a faster write, a projection, or a second engine hosting a *resizing* list - research evidence E1-E3, E5-E7 rules all three out. The fix is to give the list the same shape the bar already has: **a fixed-layout Flutter surface inside a native container that UIKit moves**. When the content never re-lays out during the drag, its pixels are cached and the movement is a Core Animation transform - the same clock as the keyboard, so there is nothing left to lag.

The hosted surface is the bar feature generalized from "a composer strip above the keyboard" to "the scrollable content area above the keyboard". The app bar, route chrome and system overlays stay in the main engine; the scrolling content and its composer live in the surface engine.

## Goals

- During an interactive keyboard dismissal (and during the keyboard's own show/hide animation) the surface's content, the composer and the keyboard move in the same display frame: every tick, the surface's presented position equals the keyboard-derived inset within 1 pt.
- The surface engine performs **no layout, no rebuild and no raster** while the keyboard moves: its view keeps a fixed frame and size and is moved by a `UIView` transform.
- The composer lives inside the surface, so there is no seam between the list and the composer at all.
- The bar mode (`CupertinoKeyboardAccessory`) keeps working unchanged, and both modes share the same native driver (keyboard tracking, notification animations, instant-collapse ownership, freeze at drag start, hidden switch, teardown).
- The example app gains a route that demonstrates the surface with a chat list + composer, so the owner can feel it on device.

## Non-Goals / Anti-Goals

- Not a generic multi-window / multi-engine framework: one hosted engine at a time, same as the bar today.
- Not a fix for the main engine's own content: the app bar and anything outside the surface rectangle stay on the old clock.
- Not a public API to host arbitrary app screens with full navigation: route transitions and full-screen overlays over the surface are a documented constraint of this version (see "Constraints").
- No work on Android; the plugin is iOS-only.
- Anti-goal: a hosted surface whose engine resizes as the keyboard moves. That is the resized-second-engine route and it has the same one-refresh lag as today (research E6).

## Constraints

- The bar stays a Flutter widget in a second engine; the surface is an additional second-engine mode, not a replacement of the bar.
- One hosted engine per app instance (the plugin's existing single-instance design: one accessory channel, one `hostedAccessoryBar` slot).
- The surface is a native subview of the FlutterView added above the Flutter rendering. Therefore: the surface rectangle must start below the app bar; main-engine routes and overlays over it are not visible while it is shown; the surface must be hidden when its route is not current, and overlays over the chat (message menus, sheets) are hosted inside the surface engine. Hiding/showing is the existing `hidden` mechanism.
- The main engine's placeholder widget must report the surface rectangle to native; it is the app's declaration of "this area is hosted".
- **The reported rectangle is full width and reaches the Flutter view's bottom.** The plugin takes its top as the content top (A) and derives the container as [A, S] from the view itself; a rect that stops short of the bottom, or a main-engine bottom bar/dock under the surface, is out of contract (the widget logs a violation and uses A only). v1 therefore has no main-engine chrome below the surface.
- **The main engine is inset-immune while a surface is hosted**: the placeholder page uses `resizeToAvoidBottomInset: false`, no `viewInsets`-driven padding, and a static app bar. The plugin does not publish the drag inset to the main engine in surface mode (the surface moves natively), the engine's own notification animation still runs, and the placeholder's rect must not change with the keyboard. A collapsing / large-title app bar is a non-goal for v1: A must be constant for the surface's lifetime (rotation and size changes excepted).
- **The surface engine view is transparent, like the bar's.** The page background stays in the main engine (the app's wallpaper layer); the hosted app paints only its rows and composer surfaces. The B-tall strip below the engine view at rest is painted by the main engine in the composer's colour (one line in the app: a bottom `ColoredBox` of height `MediaQuery.padding.bottom`), so the background is continuous across the seam.
- **iOS 15+ floor**, same as the bar: below it, or if the engine fails to start, the widget renders an app-supplied `fallback` child (default `SizedBox.shrink`, and the docs require a real fallback for shipping apps).
- The hosted engine must ignore keyboard insets: its view is always positioned so the keyboard does not overlap it, its layout is fixed, and the hosted app must not depend on `MediaQuery.viewInsets`.
- The hosted app must not resize for the keyboard (`resizeToAvoidBottomInset: false` and no inset-driven padding). The surface's native transform replaces that behaviour.
- No new dependencies.

## Approaches Considered

1. **`resizeToAvoidBottomInset: true` + full-bleed overscan + opaque band (one engine).** Cheap and removes the tear, but keeps the one-refresh content trail. Rejected: the owner requires zero lag. (Research "Fix direction", layout half.)
2. **List in a second engine, resized as the keyboard moves.** Rejected: a resized engine view repeats metrics -> layout -> raster -> CA and is just as late (research E6), plus the whole data bridge.
3. **One engine, project the inset one frame ahead.** Rejected: implemented and reverted on 2026-11-10; the plugin's three differently-timed write producers make the correction alternate (research E11).
4. **Hosted keyboard surface: fixed-layout second engine inside a native container that UIKit moves (chosen).** The only route that removes the lag, because the moving pixels are cached and the movement is a transform on the keyboard's own clock. Cost: the scrolling content and composer move to a second isolate; app state, theme and events must cross the bridge; navigation/overlay constraints above.

## How It Works

### Geometry (the contract)

Let S = Flutter view height, A = the top of the surface rectangle (below the app bar), B = the bottom safe area (home indicator, 34 pt), H = (S - A) - B = the fixed height of the hosted engine view.

- The native container is a clipping view covering [A, S] in the FlutterView.
- The hosted engine view has a **fixed frame** of height H at the container's top (container-local y = 0) and is never resized while the keyboard moves.
- The keyboard driver gives two numbers per frame: `inset` (distance from the FlutterView bottom to the keyboard's top, 0 when gone) and `padding` = max(0, B - inset) - exactly the values the bar already uses.
- The engine view's transform is `translationY = -max(0, inset - B)`:
  - keyboard gone: inset 0 -> 0, the view sits at [A, S - B] (above the home indicator);
  - keyboard fully up: inset = keyboard height K -> -(K - B), the view's bottom sits exactly on the keyboard's top edge and its top is clipped by the container;
  - during a drag the transform follows the same number the bar's constraint uses, so the surface and the keyboard share one position source and one clock (the same guarantee the bar already has).
- The composer is the bottom of the hosted app's fixed H-tall layout, so it is always the bottom visible edge of the surface: no reserved-height widget, no Column slot, no seam.
- Because the frame never changes, `viewDidLayoutSubviews` reads unchanged bounds and safe area (the view stays below the status bar and its bottom never reaches the home indicator), so the hosted engine sees no metrics change: no relayout, no rebuild, no raster while the keyboard moves.

### Native (iOS)

- Generalize the bar into a **hosted band** protocol with two implementations: `CIKHostedAccessoryBar` (today's constraint-based bar) and `CIKHostedSurface` (a clipping container + fixed-frame engine view + transform). Both expose: attach(to:inset:), apply(inset:padding:animated:duration:curve:), freezeAtVisiblePosition(), restingPadding, and the hosting/pinning/height APIs the manager and the plugin use.
- `KeyboardManager` keeps its single driver: guide-delta tracking on the pan and display link, notification-driven animation, instant-collapse ownership, freeze at drag start, settle detection, and the debug trace. It writes to whichever band is hosted (bar or surface). No new timing logic is introduced - the surface inherits the bar's proven frame behaviour.
- The plugin gains a surface mode for the existing hosted thing: `createHostedAccessory` accepts an optional `rect` (logical points, i.e. Flutter logical px). When present:
  - create the clipping container at [rect.top, S] and host the engine view with height (rect.height - B), transform from the current inset;
  - `contentHeight` is not reported by the surface app (it is full-size): the plugin computes it from the rect and the safe area;
  - `updateHostedAccessoryRect` re-reports the rect (rotation, app-bar change) and updates the container and the engine view height (a rare, non-drag resize);
  - everything else - engine creation via `FlutterEngineGroup`, transparent engine view, accessory channel, ready queue, hidden switch, teardown - is reused unchanged.
- New method-channel calls: `createHostedAccessory` gains `rect`; add `updateHostedAccessoryRect`. The surface app uses the existing accessory channel and controller (one hosted thing at a time).
- **Suppress the surface engine's own keyboard inset.** The engine computes a view controller's inset from the keyboard frame intersected with `convertViewRectToScreen(view.bounds)` (`FlutterKeyboardInsetManager.mm:241-252`), and the plugin's `FlutterViewController` swizzle runs for every instance, including the hosted one. At the instant of a notification the surface's transform still holds the previous position, so the engine would latch an inset of (keyboard height - B) at keyboard-up and animate it on every show/hide, which would relayout the hosted content. The swizzle must therefore recognise the hosted surface's view controller (a weak reference on `KeyboardManager`) and skip both the plugin's manager hand-off and the engine's notification handler for it: the surface's inset stays 0 for its whole life, and only the main engine's controller drives the band. Verify with a trace inside the surface isolate that `MediaQuery.viewInsets.bottom` is 0 through a drag and through show/hide.
- Forward the drag state to the hosted app (`invoke('keyboardDragging', {'dragging': bool})`) when the surface is hosted, so the hosted list can pin its offset during the interactive drag (the surface transform already moves the content; letting the list scroll too would double the motion).
- **The "keyboard is up" predicate for a surface** is the manager's last notification inset (`barInset > 0.5`), not the bar's "band bottom above the view bottom" test - a surface's container bottom is the view bottom by construction and its engine view is always B above it. `startTrackingIfKeyboardVisible` gets a surface branch on that predicate; the settle detection and the trace read the surface engine view's *presentation* frame (the animated transform), not its model frame.
- **Rect changes** (rotation, app-bar change) are applied only when tracking is idle: a rect update that arrives mid-drag is deferred until the settle; the engine view height and container top then update in one non-drag resize.
- **Hide and focus**: hiding a native view does not resign first responder, so on hide the plugin forwards `invoke('hidden', {'hidden': true})` to the surface isolate *before* hiding, resigns the surface view controller's first responder as a safety net, stops tracking and clears the band reference. The hosted app must unfocus its composer on that event so Flutter's focus state stays consistent; the keyboard is expected to be dismissed when the chat is hidden (the example does not restore focus on return).
- **Ownership**: one hosted thing per app. A create while another is alive is last-wins (the current behaviour), with two additions: the displaced widget is told through a `hostedAccessoryReleased` event on the main engine that carries the displaced host's id (so the widget that displaced it does not drop its own ownership), and a surface re-hosts when it is visible and its route is current again. Dart state survives; only the second engine is recreated (a frame of blank + a fresh composer focus state). The bar does not re-host on its own (documented limitation); v1 does not add multi-host support.
- Trace: the `frame` line gains the surface's transform and the presented position, so a device run can assert surface vs guide on every tick.

### Main isolate (Dart)

- `CupertinoHostedKeyboardSurface({required String entrypoint, required String libraryURI, CupertinoHostedInputAccessoryController? controller, bool hidden = false})`: a placeholder widget that takes the space of the hosted area, reports its rect with the existing `RectObserver` (post-frame, logical px), creates the hosted thing with that rect, updates it when the rect changes, forwards `hidden`, and tears down on dispose. It fills its parent (the app's body under the app bar) and paints nothing; the native surface is drawn above it.
- It reuses `CupertinoHostedInputAccessoryController` and the existing event stream; no new bridge concept.
- It uses `CurrentRouteAware` to set `hidden` when its route is not current, so a pushed main-engine route is not covered by a stale native surface.
- The example wraps it in `CupertinoInteractiveKeyboard` so the dismissal gesture is armed over the surface rectangle (the existing rect-reporting path), and keeps the app bar in the same screen.

### Surface isolate (Dart)

- `runCupertinoKeyboardSurface(builder)`: like `runCupertinoAccessory`, but a full-size host - no content-height sizer, no intrinsic-height contract. The builder gets the same controller.
- The hosted app owns its background, list, fade/band and composer, laid out against the fixed H and ignoring `MediaQuery.viewInsets` and `MediaQuery.padding` (both are 0 by construction). It must not resize for the keyboard.
- The hosted app pins its scroll offset (or swaps the scroll physics) while the forwarded `keyboardDragging` is true, exactly as an interactive dismissal behaves natively.
- Composer edits stay in the surface; the app's state flows through the bridge (draft, send, messages, theme/palette).

### Example app

- New route `/hosted_surface` (catalog entry): main isolate has the AppBar and a `CupertinoHostedKeyboardSurface` body; surface isolate runs a chat screen - message list (reverse), composer, theme and messages sent from the main isolate, draft/send received back.
- The existing `/hosted_accessory` bar route stays as the bar demo; the two are separate screens and never host at the same time (one hosted thing at a time).
- README: a "Frame-locked chat" section documenting the surface, its constraints (app bar outside, overlays/navigation inside or hidden), and the one-hosted-engine limit.

## Verification

- Swift geometry checks (`ios/KeyboardGeometryTests/main.swift`): `surfaceTranslation(inset:restingPadding:)` = -max(0, inset - B) for inset 0, B/2, B, B+1, K, and clamping; `surfaceContentHeight(rect:safeBottom:)`; the existing bar checks still pass.
- Widget tests (`test/hosted_surface_test.dart`, existing mock channel): the surface reports its rect (once, and again on change), creates the hosted thing with that rect, forwards `hidden` and pushes `keyboardDragging`/`invoke` events to the controller, and tears down on dispose; the widget occupies its parent and paints no opaque surface (no second inset path in the main engine).
- Existing gates stay green: `flutter test` (all current tests), `flutter analyze` 0 errors, `ios/KeyboardGeometryTests/run.sh`, `flutter build ios --no-codesign --simulator`.
- Device milestone (the owner): build the example, open `/hosted_surface`, turn the trace on, drag the keyboard down and up fast. **Pass:** on every `frame` tick the surface's presented bottom is within 1 pt of the guide-derived band; the surface engine logs no metrics push during the drag (add a debug frame counter to the surface host); the composer stays glued. **Fail:** any steady offset, which would mean the guide read itself is late - then the existing bar behaviour is the limiter and the fix moves to the same prediction the engine uses, not to geometry.
- Manual feel check: fast flick up and down, slow drag, cancel mid-drag, keyboard open/close via tap, home-indicator strip at rest, multiline composer growth, typing with the keyboard up (caret and scroll unaffected).
- Inset silence: the surface isolate traces `MediaQuery.viewInsets.bottom` and it stays 0 for the whole drag and through a show/hide; the hosted app's frame counter stays at 0 during a drag (no rebuild, no layout, no raster).

## Builder Check - the Lead's Calls

A fresh builder's read of the first draft produced seven open questions. All seven are implementation or product-shape decisions that do not change what gets built, so they are settled here; the owner only has to approve the design and pick the scope (plugin+example first, or the app port folded in).

| # | Question | Call |
|---|---|---|
| 1 | What makes the driver consider the keyboard up for a surface? | The manager's last notification inset (`barInset > 0.5`); settle/trace read the engine view's presentation frame. |
| 2 | Must the rect be inset-immune; does the main engine still get inset writes? | Yes: the page is `resizeToAvoidBottomInset: false`, no inset padding, static app bar, no drag-inset write to the main engine; the placeholder rect is constant. |
| 3 | Resign the composer's first responder on hide/teardown? | Yes: forward `hidden` to the surface isolate first, then resign the VC's first responder, stop tracking and clear the band; the hosted app unfocuses on that event. |
| 4 | Second hosted thing while one is alive? | Last-wins plus a `hostedAccessoryReleased` event; the displaced widget re-hosts when visible and current again. Multi-host is out of scope. |
| 5 | Opaque or transparent surface; who paints the B strip? | Transparent engine view; background and B strip are the main engine's; the app paints the strip in the composer's colour. |
| 6 | What shows when hosting is impossible (iOS 13/14, engine failure)? | iOS 15+ floor with an app-supplied `fallback` child (defaults to empty); shipping apps must pass a real fallback. |
| 7 | Must the rect reach the view's bottom? | Yes, full width and bottom-reaching; the plugin uses only the rect's top and derives the rest from the view. |

## What Is Left To The Builder

- **The app port (`../uptalk`)** is its own plan, not part of this one. The chat page's list + band + composer + fade move into the surface isolate; the app bar, background layer, overlays and navigation stay in the main isolate. The bridge surface is the whole chat state (message stream, game state, palette/background selection, typing, read receipts, draft/send, question docks) and the overlay story (message actions, sheets, score dock) has to be decided: either hosted inside the surface, or the surface is hidden while a main-engine modal is up. This is the expensive half of "the lag gone" in the real app and it needs its own spec.
- **The hosted VC's keyboard inset** is suppressed in the swizzle (see "How It Works"); the remaining open question is whether skipping the engine's notification handler leaves any engine-side state that a later real notification needs. A device run is the check: the surface isolate's `MediaQuery.viewInsets.bottom` must stay 0, and a keyboard show/hide after the surface is created must not move the hosted content.
- **a11y across the translated view**: semantics frames are converted through the view transform, but the hosted layout is taller than the visible area at keyboard-up and VoiceOver focus over clipped content is untested. Needs a device pass; if it misbehaves, inset the hosted app's semantics or reduce the fixed height.
- **Text input / IME inside the surface** (caret reveal, autocorrect bar geometry) needs a device pass; the engine already gives the hosted view its own text-input plugin.
- **Route transitions**: v1 hides the surface when its route is not current; the transition itself is abrupt (the surface disappears rather than sliding). Polishing it (snapshot handover or a native transition) is a follow-up.
- **iOS 26** native keyboard tracking changes (react-native-keyboard-controller reports a presentation-layer break) must be retested per OS version.
- Naming: the surface reuses `CupertinoHostedInputAccessoryController` and the accessory channel to keep the diff small; if the surface ships, consider sharing a neutral controller name and an id-based channel for more than one hosted engine.
- Docs: README section, CHANGELOG entry, and the version bump when it ships.
