# Design Doc: frame-locked chat in uptalk's workspace bottom panel (behind surface)

- Date: 2026-11-11
- Status: approved by the owner ("yes. write plans etc what you need and implement")
- Plugin feature this builds on: `docs/superpowers/specs/2026-11-11-hosted-keyboard-surface-design.md` (forward surface, shipped in the plugin as eac8d28)
- Scope agreed with the owner: the workspace bottom panel chat only; the full-screen chat route is removed.

## Intent & The Why

The workspace bottom panel embeds the chat inside a morphing, rounded sheet. The owner wants the
message list to stop trailing the keyboard during an interactive dismissal. The plugin's forward
surface (a second engine moved by a native transform) fixes that, but a surface **above** the Flutter
view hides everything the main engine paints over the chat: the panel's message flight, the
message-action sheet, the background picker, the template/refill sheets. The panel is built around
those, so the surface must sit **behind** the Flutter view: the chat page paints a transparent hole
where the list lives, and the main engine keeps drawing the panel chrome, the band and every overlay
above the live, natively-moved list.

## Goals

- The panel chat's list moves with the keyboard frame for frame (no trail), while the main engine
  keeps its overlays, the message morph flight and the panel's own animations.
- The app keeps its widgets and state in the main isolate: the surface renders the list rows from a
  bridged view-model; taps/actions come back over the bridge.
- Panel resizing/morphing needs no per-frame native sync: the hole is Flutter-painted, the surface's
  engine layout is bottom-anchored and fixed; only the keyboard moves it (natively).
- The full-screen chat route is gone; the chat menu and notification deep links open the workspace
  panel with that chat.

## Non-Goals / Anti-Goals

- Not the full-screen chat route (removed).
- Not moving the message rows' *logic* into the surface: the main isolate stays the source of truth
  (Firestore, game state, question logic, overlays, navigation).
- Not a Flutter-composited workaround (snapshot overlays, transformed Flutter views): rejected as
  artefact-prone (one-frame strips at the band edge), the exact failure class this project removes.
- Not the band/composer: the chat field already rides the keyboard through the plugin's hosted bar;
  the band (typing row, reply preview, docks) stays in the main engine for v1.

## Constraints

- iOS 15+; the plugin is a path dependency while this is developed, a pushed ref when it ships.
- One hosted thing per app (plugin limitation): the panel surface replaces the hosted bar on the
  chat screen; other screens keep the bar.
- The main FlutterView becomes non-opaque while a behind surface is live. The plugin sets
  `isViewOpaque = false` on create and restores it on teardown as a safety net, but the app must set
  it on its root FlutterViewController **before the first frame** (the engine's surface is created
  from that flag, so a late change may not open the hole). The app's chat page paints nothing in
  the hole.
- Touch passthrough is native and explicit: the plugin only lets touches through to the surface while
  the app says the chat is interactive (`setHostedSurfaceInteractive`); with a sheet/dialog open the
  main engine owns the touches.
- The surface is translated by the keyboard inset only (`translation = -inset`, resting offset 0); its
  engine view is the screen size and never resizes while the keyboard moves.
- The hole's background belongs to the surface isolate (the app sends the palette/wallpaper); the
  main engine paints the rest of the page.
- No new dependencies.

## Approaches Considered

1. **Forward surface (shipped plugin mode).** Simple, but hides the panel's flight, sheets and
   overlays. Rejected for the app.
2. **Snapshot overlay during the drag.** No second engine, days of work, but leaves a one-frame strip
   at the list/band edge and stales while dragging. Rejected.
3. **Behind surface (chosen).** Plugin addition: the surface container is inserted below the
   FlutterView; the chat page paints a transparent hole; the plugin passes touches through to the
   surface while the chat is interactive. All app UI and overlays stay in the main engine.

## How It Works

### Geometry

- Surface container: a full-screen native view below the FlutterView (sibling of it), containing the
  second engine's view at the screen size.
- Translation: `y = -inset` (the keyboard inset), clamped to [-height, 0]; animated with the
  keyboard's notification duration/curve on show/hide and with the plugin's owned collapse.
- App-side layout: the list is bottom-anchored in the surface engine with a bottom padding equal to
  the band height + rest gap (bridged; changes only when the band changes, never per keyboard frame).
- The hole: the app's list area is transparent; the panel chrome, the band and overlays are painted
  by the main engine above it. Panel resize/morph changes only the hole's shape in Flutter; no native
  sync and no engine relayout.
- Touch passthrough: the plugin swizzles the main FlutterView's `hitTest:withEvent:` and returns nil
  for points inside the live hole while the chat is interactive and its route is current, so the
  surface behind receives them. The live hole = the reported hole (the list area above the app's
  band) with its bottom raised by the keyboard's *presented* inset, clamped to the view
  (`KeyboardGeometry.liveHole`); the band and the chrome keep their touches. The widget withholds
  passthrough automatically under a pushed route or a modal (the hole stays open so a sheet draws
  over the live list); the app's `interactive` flag can withhold it further.

### Native

- `NativeAccessoryConfig.behind: Bool`: create mode. The surface is inserted
  `flutterView.superview?.insertSubview(surface, belowSubview: flutterView)`, engine view at screen
  bounds, resting padding 0 (so the existing `surfaceTranslation` is `-inset`). The surface stores
  the app's hole rect; the keyboard inset raises the live hole's bottom for the passthrough test.
- The hit-test bridge: `FlutterView` is not in the module headers, so the plugin looks it up with
  `NSClassFromString("FlutterView")`, installs a `hitTest:withEvent:` replacement with
  `class_replaceMethod`, and returns nil only for points inside the live hole while the app's
  interactive flag is on. The original implementation is called directly.
- `setHostedSurfaceInteractive(bool)`: stored; the hit-test swizzle consults it plus the hole and the
  live inset.
- The main FlutterViewController's `isViewOpaque` is set false while a behind surface lives
  (restored on teardown); the engine's keyboard notifications are suppressed for the surface VC
  exactly as in the forward mode.
- Hide: the native surface is hidden and the app's widget shows its fallback (the page's background)
  in the hole, so a covered route never shows the window background.

### Main isolate

- `CupertinoHostedKeyboardSurface({behind: true, fallback: ...})`: reports the hole rect, creates the
  host with the rect, forwards hidden/interactive; when it is not hosting its route, or while hidden,
  it renders `fallback` (the page background) instead of the transparent hole. For behind mode it
  also forwards `hidden` to native so the surface does not paint under an opaque page.
- New controller/channel surface: `setHostedSurfaceInteractive(bool)`, exposed on the controller and
  as a platform method; widget tests cover the call and the fallback behaviour.

### Surface isolate

- `runCupertinoKeyboardSurface` as shipped, plus a bottom inset (band height) and the palette handed
  over the bridge; the first milestone (probe) renders a placeholder list, the next one the real
  rows.

### App (uptalk)

- Remove the full-screen chat: delete the `/chats/:chatId` route; make the chat menu
  (`direct_chat_menu_page.dart:159`) and notification deep links (`notifications.dart:22`) open the
  workspace with that chat in the panel.
- Keep the panel chat's main-engine band/composer/flight/overlays; the list area becomes the hole
  with the surface behind. Messages/game/palette bridged to the surface; row interactions bridged
  back. The morph flight's latest-message rect is bridged from the surface when the flight runs.

## Verification

- Plugin: widget tests for the behind flag/interactive call/fallback, geometry unchanged, iOS
  simulator build; forward bar/surface tests stay green.
- App: `flutter analyze` clean, app tests; the probe runs on device.
- Device (owner): in the panel, drag the keyboard down/up fast — the list must stay glued to the
  keyboard; open a message-action sheet and the background picker over the chat (they must draw over
  the live list and dim it, and their buttons must work); trigger the message morph flight (panel
  open) — it must land on the message; collapse/expand the panel — the list is revealed/clipped with
  no lag; push a route and come back — no window-background flash.

## What Is Left To The Builder

- Stage 2: the real list port (row widgets rendered in the surface isolate from a view-model, taps
  bridged back), the latest-message rect bridge for the morph flight, the band/fade integration.
- Stage 3: wallpaper/palette matching inside the surface, rotation/landscape, a11y across the two
  views, the final fullscreen removal polish, plugin push + ref bump.
- `isViewOpaque` affects the whole app while a behind surface is live; verify no visual/perf
  regressions on other screens during the transition and restore it on teardown.
