# Verification design — keyboard release makes the composer jump to the bottom

Task: task-4 (verification-analyst). Read-only audit; no product file was touched.
Date: 2026-11-09. Repo under audit: `cupertino_interactive_keyboard` @ `860b18f`.
Consumer: `/Users/vitekvitek/development/uptalk` (plugin pinned from git `master`, `pubspec.yaml:69-72`, lock `1.1.1`).
Engine source used for the mechanics: `/Users/vitekvitek/development/flutter/engine/src/flutter` (3.47.7, engine `deb287481e`).

---

## 0. TL;DR — the shortest empirical route

1. **One device run with ~10 log sites** (all `#if DEBUG`, guarded by a single `CIKTrace.enabled` bool) discriminates all four candidate causes **in a single drag-and-release**, because each candidate produces a *different first divergent field* (§1.6 decision table). No engine changes are needed: `physical_view_inset_bottom` is observable from Dart as `MediaQuery.viewInsets.bottom`, and echo-able natively through the public-shaped selector `physicalViewInsetBottom` (`FlutterViewController.mm:2317`, same IMP trick the plugin already uses at `KeyboardManager.swift:283-299`).
2. **This machine can drive the repro two ways**: the owner's iPhone is paired and visible to `devicectl` (`Worp`, `00008101-000C58660AD8001E`, iOS 26.5, available), and a simulator (`CIK iPhone 17 Pro`, iOS 26.4) boots here in seconds with the software keyboard enabled (hardware keyboard already detached: `ConnectHardwareKeyboard = 0`). The simulator is the right place to iterate on the trace plumbing; the iPhone is the only authoritative run (§2).
3. **No existing static check can catch this class of bug**, and the one host-runnable suite that exists (`ios/KeyboardGeometryTests/run.sh`, 15 checks, all passing today) is **not wired into CI** (`.github/workflows/test.yml:10-33`). The cheapest useful regression net is a pure "release hand-off" state-machine check in the same swiftc harness plus a small assertion script over a captured trace (§3).
4. Cost of the whole verification loop: instrumentation 2-3 h, one owner run ~15 min, trace assertions ~1 h. Recommended order in §5.

---

## 1. Device trace — smallest instrumentation that discriminates in one reproduction

### 1.1 Shape

One new DEBUG-only file `ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/CIKTrace.swift` (proposal, not written):

- `static let enabled`: read once from `ProcessInfo.processInfo.environment["CIK_TRACE"] == "1"` or launch argument `-CIKTrace 1`; `#if DEBUG` only, `false` in release. Every site starts with `guard CIKTrace.enabled else { return }`, so the cost when off is one bool test — zero allocations, zero formatting.
- One monotonic clock: `CACurrentMediaTime()` in **milliseconds with 3 decimals** (the report's "a few ms apart" is the measurement we need to resolve).
- Two sinks from the same line: `NSLog("CIKTRACE ...")` (appears in `flutter run` and `devicectl --console`) **and** a ring buffer in `Documents/cik-trace-<pid>.log` (~4000 lines, then one `TRACE-CAP` line and stop; `try? handle.synchronize()` after every write) so nothing is lost when the console is not attached.
- Change-only logging: the two hot paths (`trackInteractiveKeyboard`, `syncInset`) already return early when nothing changed (`KeyboardManager.swift:266`), so putting the log *after* the change test is automatic rate limiting. Add a heartbeat row every 15 display-link ticks and a hard cap of 3000 lines/session.

### 1.2 Native hook points (all inside the plugin)

| # | Hook (file:line) | Event | Fields to log |
|---|---|---|---|
| N1 | `FlutterViewController+Swizzle.swift:20-35` (inside all three handlers, before the `KeyboardManager` call) | every keyboard notification, plus **which VC** got it | `name`, `vc=main|accessory|other` (`self === KeyboardManager.shared.flutterViewController`), `begin`, `end`, `duration`, `curve`, `isLocal`, `engineWouldIgnore` (mirror of `FlutterKeyboardInsetManager.mm:91-123`), tracking state |
| N2 | `KeyboardManager.swift:86-89` `willProcessKeyboardNotification` | the moment the plugin hands the release to the engine | `STOP`, notification name, `lastReportedInset`, `bandBottom` at that instant |
| N3 | `KeyboardManager.swift:158-171` / `:173-183` | tracking start / stop | `START/STOP`, `physicalViewInsetBottom`, `targetViewInsetBottom`, band, drag state; also **session id** so a start/stop pair can be counted |
| N4 | `KeyboardManager.swift:191-217` `trackInteractiveKeyboard` | per display-link tick, change-only | `tick`, `bandBottom`, `inset`, `lastReportedInset`, `targetViewInsetBottom`, `physicalViewInsetBottom`, `isDragging`, `staticTicks` |
| N5 | `KeyboardManager.swift:266-275` (after the early return, around the write) | every inset write + which branch was taken | `SYNC`, `inset`, `presentationCorrected=yes/no`, `invalidatedEngineAnimation`, then read-back `physicalViewInsetBottom` via the IMP trick used at `:283-299` (`@convention(c)(AnyObject, Selector) -> CGFloat`) |
| N6 | `KeyboardManager.swift:238-244` | `hostedAccessoryBar == nil` while a keyboard is up | `BAND=nil` (throttled to 1/s) — a nil band silently kills sync |
| N7 | `KeyboardManager.swift:324-340` | engine animation cancellation | `INVALIDATE` — if this fires on the release frame, the engine's own animation was killed and never restarted |
| N8 | `CIKHostedAccessoryBar.swift:92-95` `layoutSubviews` (+ `:97-103`) | every bar layout pass, change-only | `BAR`: `bar.frame` in window, `superview.keyboardLayoutGuide.layoutFrame` (iOS 15+, read from the bar's superview = Flutter view), `window.bounds`, `safeAreaInsets.bottom`, `isHidden`, `barHeight` |
| N9 | `CupertinoInteractiveKeyboardPlugin.swift:148-159` + `:316-324` | Dart asks to hide/show the bar | `HIDDEN=yes/no` — candidate (b) is decided here |
| N10 | `CupertinoInteractiveKeyboardPlugin.swift:337-351` + `:232-234` | bar teardown / height change | `TEARDOWN`, `HEIGHT` |
| N11 | `KeyboardManager.swift:28-33` + trace helper | private interactive-dismissal notification and any other private keyboard notification | `PRIV` + name. Implement as a second, trace-only `NotificationCenter` observer with `name: nil` filtered to names containing `"Keyboard"` — captures private notifications nobody documents (the owner suspected "it maybe sends some notification") |

Cheap addition with high diagnostic value: in N1 also log whether the notification was delivered while a pan recognizer was still `.began/.changed` (`KeyboardManager.swift:66-71`) — that distinguishes "release notification" from "arbitrary notification during the gesture".

### 1.3 Dart-side hooks

- In the plugin (reusable by every consumer): `lib/src/debug/…` `CikTrace` guarded by `const bool.fromEnvironment('CIK_TRACE')`, plus a `WidgetsBindingObserver` that logs **on `didChangeMetrics` only** (fires exactly once per engine metrics push, so one line per animated frame without a 60 fps poll): `viewInsets.bottom`, `padding.bottom`, `View.of(context)` size.
- In the consumer app (uptalk), on the chat page: log per metrics change the list `ScrollController.offset`, `position.maxScrollExtent`, the resolved `_listBottomPadding` (`direct_chat_page_state.dart:223`) and `_bottomBandHeight`/`_composerHeight` (`:302-315`), plus the Scaffold body constraints (a `LayoutBuilder` wrapper). This is what decides whether the *list* jumps because of the engine inset (c) or because of the app's own arithmetic.
- The plugin's own example already has the repro surface without touching uptalk: `example/lib/keyboard_accessory.dart:139-159` (reverse `ListView` inside `CupertinoInteractiveKeyboard` + `CupertinoKeyboardAccessory` at `:152-157`).

### 1.4 One-reproduction script (what the owner does)

1. Open the chat screen, tap the composer, let the keyboard settle (~0.5 s).
2. Drag the keyboard down ~40 % and **release** (this is the reported failure, cancel case). Wait 1 s.
3. Drag down ~70 % and release (dismiss case — control).
4. Reopen, then three rapid drags with alternating release, no pauses (settling/leftover-tracking case).
5. Stop; send the trace file (or copy the console text).

### 1.5 Delivery of the log (ranked)

| Rank | Path | Command | Notes |
|---|---|---|---|
| 1 | Ring buffer → `Documents`, pulled after the run | `xcrun devicectl device copy from --device 00008101-000C58660AD8001E --domain-type appDataContainer --domain-identifier app.uptalk.uptalk --source Documents/cik-trace.log --destination /tmp/` | Verified flag support (`devicectl device copy from --help`). Works tethered or wireless, no console babysitting |
| 2 | Console while `flutter run` | `flutter run -d 00008101-000C58660AD8001E --dart-define=CIK_TRACE=true` then `DEVICECTL_CHILD_CIK_TRACE=1` is *not* needed for `flutter run` (use the Xcode scheme env var); NSLog lines land in the terminal | Owner can copy-paste; no extra tooling |
| 3 | Attach to an installed build | `xcrun devicectl device process launch --console --terminate-existing --device 00008101-000C58660AD8001E app.uptalk.uptalk` | Verified `--console` exists. Env vars pass as `DEVICECTL_CHILD_CIK_TRACE=1` |
| — | `Console.app` | filter `CIKTRACE` | Works, but the owner has to keep it open; ring buffer is more reliable |

### 1.6 Decision table — first divergent field decides the cause

All rows are read off the *same* trace; the first row whose signature matches is the answer.

| Signature in the trace | Candidate | Meaning / next step |
|---|---|---|
| At the release frame, `BAR` shows `bar.frame.maxY` (and `guide.minY`) moving to the Flutter view's bottom while the release notification's `end.minY` is still above the screen bottom; `SYNC` then computes inset ≈ 0 | **(a) bar / guide collapsed** | The `keyboardLayoutGuide` top went to the view bottom while the keyboard is visually still up (constraint at `CupertinoInteractiveKeyboardPlugin.swift:219-224`). Fix = stop relying on the guide being the live band across the release |
| `BAR`/`SYNC` stay glued to the keyboard, insets stay smooth, but a `HIDDEN=yes` (or `TEARDOWN`) row appears on/just after the release | **(b) app hid or remounted the bar** | Traced to `CupertinoInteractiveKeyboardPlugin.swift:316-324` ← `CupertinoKeyboardAccessory.hidden` ← uptalk `direct_chat_page_state.dart:756-771, 774-782`. Fix in the app (do not hide on keyboard events) or in the widget contract |
| `BAR`/`SYNC`/`physicalViewInsetBottom` smooth, but the Dart lines step at the release (body height or list offset jumps in one frame while `viewInsets` is smooth) | **(c1) app layout jump** | The Flutter side reacts twice: the engine inset drives the `Scaffold` body (`direct_chat_page_scaffold.dart:72`) *and* the app reserves the bar height (`direct_chat_page_body.dart:1112-1123`). Fix is arithmetic on the app side |
| `SYNC` shows `physicalViewInsetBottom` jumping (0 → live or live → 0 in one frame) with no engine ramp, and the bar stays glued | **(c2) engine inset jump** | The plugin wrote the value or the engine animated from a stale start (`FlutterKeyboardInsetManager.mm:273` reads `physicalViewInsetBottom` as the animation start). Check `N5` read-back and `N7` |
| `N2 STOP` logged, `N7 INVALIDATE` also logged at the release, then **no** further `SYNC` and Dart `viewInsets` stops changing while the keyboard animates | **(d) engine ignored/froze the release** | The engine early-returns when `targetViewInsetBottom == calculatedInset` (`FlutterKeyboardInsetManager.mm:66-69`) or its animation was invalidated without a restart (`KeyboardManager.swift:324-340`). Fix = hand a differing target before stopping |
| `N1` shows `vc=accessory` handling `willHide`/`willChangeFrame` and `STOP` firing from it mid-gesture | **(e) cross-VC stop** (not in the brief) | The swizzle is on the **class** (`FlutterViewController+Swizzle.swift:9-16`), so the second engine's `FlutterViewController` (created at `CupertinoInteractiveKeyboardPlugin.swift:249`) runs the same handlers and calls `KeyboardManager.shared.willProcessKeyboardNotification` too. Log which VC; if a stop comes from the accessory VC the tracking can end before the main keyboard moves |

### 1.7 Cost

- `CIKTrace.swift` + N1-N11: 150-200 LOC, 2-3 h, DEBUG-only, no release cost, no new dependency.
- Owner run: one build + ~20 s of gestures, log file in `Documents` (~10 min).
- The same trace, unchanged, is the before/after oracle for the fix: the decision-table row that matched must be gone and §4's objective criteria must hold.

---

## 2. Local feasibility (commands actually run)

### 2.1 Evidence

| Command | Output summary |
|---|---|
| `xcodebuild -version` | Xcode 27.0 (27A266a) |
| `xcrun simctl list runtimes` | iOS 18.4, iOS 26.4, iOS 27.0 installed |
| `xcrun simctl list devices available` | exactly one: `CIK iPhone 17 Pro (0D4639F2-…)`, iOS 26.4, Shutdown |
| `xcrun simctl boot 0D4639F2-…` → `list devices booted` → `shutdown` | booted cleanly (`Booted` in the list), shut down cleanly — **simulator is bootable here** |
| `defaults read com.apple.iphonesimulator ConnectHardwareKeyboard` | `0` → the software keyboard **will** show in the simulator (the usual blocker is already off) |
| `xcrun devicectl list devices` | `Worp` — iPhone 12 mini, `00008101-000C58660AD8001E`, **available (paired)**; the simulator shown as *simulated* |
| `flutter devices` | `Worp (wireless) • 00008101-… • ios • iOS 26.5` + macOS. No simulator until one is booted |
| `xcrun devicectl device copy from --help` | supports `--domain-type appDataContainer` + `--destination` → **file pull from the app container works** |
| `xcrun devicectl device process launch --help` | supports `--console` (bridges the app's stdout) and `--terminate-existing` |
| `xcrun simctl io --help` | `screenshot`, `recordVideo` (frame evidence) — **no input injection** |
| `which idb` / `idb list-targets` / `which idb_companion` | client exists in pyenv, **companion missing** → `idb list-targets` tracebacks out; idb is not usable as-is |
| `which idevicesyslog` | not found (no libimobiledevice console bridge) |
| grep `RunnerUITests\|XCUITest` in `example/ios/Runner.xcodeproj` | **0 hits** — only the template unit bundle `RunnerTests` exists |
| `ios/KeyboardGeometryTests/run.sh` (compiled from a `/tmp` copy so the repo stays untouched) | `all checks passed` (15 checks, exit 0) — the suite is green *today*, i.e. it does not catch this bug |
| `git status --porcelain` in the repo | empty (read-only preserved) |

### 2.2 Simulator repro — realistic, right iteration loop, not authoritative

Harness (≈10 min once, no product changes):

```sh
xcrun simctl boot 0D4639F2-F8D3-4F06-9F11-2EB89B4DDDFE && open -a Simulator
cd example && flutter run -d 0D4639F2-F8D3-4F06-9F11-2EB89B4DDDFE --dart-define=CIK_TRACE=true
# optional frame evidence in a second shell:
xcrun simctl io 0D4639F2-F8D3-4F06-9F11-2EB89B4DDDFE recordVideo /tmp/cik-repro.mp4
```

Then: open the hosted accessory screen (`example/lib/keyboard_accessory.dart:152`), tap the field, press-drag the keyboard down ~40 % with the mouse and release. The dismissal gesture is the plugin's own hidden `CIKScrollView` (`keyboardDismissMode = .interactiveWithAccessory`, `CIKScrollView.swift:16-23`, recognizer re-attached to the superview at `:46-51`), so a plain mouse drag on the list is enough — no UIKit access to the system keyboard needed.

Caveats that make the simulator *not* authoritative: the mouse synthesizes the drag, the spring curve/hardware timings differ from a real iPhone, and a simulator has no third-party keyboard/accessory complexity. Use it to prove the trace plumbing and to try the fix; confirm on `Worp`.

### 2.3 Automation options and verdicts

- **XCUITest**: would work (`press(forDuration:thenDragTo:)` on the keyboard area) but needs a UI test target added to `example/ios` (product-file change, ~1-2 h) and cannot assert frame-level pixels without screenshot diffing. **Not worth it now** — the manual 2-minute checklist in §4 is cheaper and catches more.
- **idb**: no companion binary; installing it (`brew tap facebook/fb && brew install idb-companion`) buys simulator touch injection, which the mouse already does. Physical-device support needs the companion too. **Skip.**
- **`simctl spawn` / `simctl io`**: no touch injection. **Skip.**
- **Physical-device automation**: not needed; the owner performs 4 gestures.

---

## 3. Static checks today, and the smallest new regression net

### 3.1 What exists

| Check | Covers | Can it catch this bug class? |
|---|---|---|
| `flutter test` — `test/hosted_input_accessory_test.dart` (314 l), `test/cupertino_interactive_keyboard_test.dart` (282 l), `test/cupertino_accessory_test.dart` (117 l) against `test/mock_cupertino_interactive_keyboard.dart` | channel call/response wiring, the accessory widget's height reservation and lifecycle, hosted-bar events | **No** — pure Dart with a mocked platform; no UIKit, no layout, no animation, no keyboard |
| `ios/KeyboardGeometryTests/run.sh` (`run.sh:1-13`) + `main.swift` (15 `expect` calls) | `inset` math, docked/floating classification, hosted bar height, `shouldStopTracking` pure decision (`KeyboardGeometry.swift:18-20, 46-48, 33-38, 60-66`) | **No, as written** — it never sees a notification, a guide, or an animation. It is the right *place* for a check, not the right *content* |
| `flutter analyze` (`analysis_options.yaml` includes `package:lint`) | style/type only | No — and note it is **not in CI** either |
| CI (`.github/workflows/test.yml:10-33`) | `flutter test`, two `flutter build ios --no-codesign`, `dart pub lish --dry-run` | **No — and it does not even run `run.sh`** |

### 3.2 Smallest new check that fails if the fix regresses

**A. (recommended, ~30 min) Make the notification filter pure and cover it.**
`KeyboardManager.swift:96-109` (`isIgnoredByEngine`) is a pure decision hidden behind `Notification`/UIKit. Move it to `KeyboardGeometry` as `static func shouldIgnoreKeyboardNotification(name:frame:isLocal:)` and add 5 checks to `ios/KeyboardGeometryTests/main.swift`: willHide never ignored; zero-frame `willChangeFrame` ignored; non-local ignored; *empty but non-zero* frame **not** ignored; willShow never ignored by frame. This is exactly the condition the code comments warn about ("a zero-frame change posted while the keyboard is dragged cannot stop the tracking and freeze the inset"), so a regression here freezes the composer mid-drag.

**B. (the real oracle for this bug, ~2-3 h incl. refactor) A release hand-off state-machine check.**
Extract the tracking decision from `KeyboardManager.swift:191-217` into a tiny UIKit-free value type (fields: `lastReportedInset`, `lastBandBottom`, `staticTicks`, `tracking`; one `step(bandBottom:isDragging:) -> .write(CGFloat) | .stop`) and replay a scripted frame sequence in `run.sh`: 1 open frame, 20 drag frames down, then 8 release frames back up. Assert (i) every drag frame yields a write equal to the band-following inset, (ii) no stop before 5 static frames, (iii) the last write before the stop **equals** the band at the release frame (the hand-off value the engine starts its animation from — `FlutterKeyboardInsetManager.mm:273`). This is the only check that would actually fail if someone re-touches the release path (early stop, zeroed inset, stale band).

**C. (15 min) Wire `run.sh` into CI** as its own step in `.github/workflows/test.yml` (and `flutter analyze` too). Today a green CI says nothing about the Swift source.

**D. (keeps it fixed without a device farm, ~1 h) A trace assertion script.**
A ~60-line `python3`/`awk` checker over the captured `CIKTRACE` log that asserts §4's objective criteria (monotonic inset on release-cancel, `|bar.maxY - guide.minY| ≤ 0.5` on every sample while the keyboard is visible, no `HIDDEN=yes` during a gesture, `started == stopped` sessions). Run it on the log the owner sends back, and re-run it on the post-fix log. That is the cheapest "before/after" evidence that the fix holds, and it costs no new framework.

---

## 4. Device acceptance criteria (the fix is accepted only if all pass)

Objective, from the trace:

- **O1** While the keyboard is visibly open, every sampled frame has `|bar.frame.maxY − guide.minY| ≤ 0.5 pt` **and** `bar.frame.maxY < view.bounds.maxY` (no frame where the composer is at the screen bottom under a visible keyboard).
- **O2** On release-cancel, `physicalViewInsetBottom` changes monotonically (no sign flip) towards the resting inset and reaches it within the keyboard's own animation duration (≤ duration + 2 frames), with a change on ≥ 80 % of the vsyncs (it is an animation, not a step). No single frame delta larger than the drag's own per-frame delta + 4 pt.
- **O3** No `HIDDEN=yes` and no `TEARDOWN` row between gesture start and settle.
- **O4** Tracking sessions: `starts == stops` after each gesture; no session left running 1 s after settle.
- **O5** Release-dismiss ends with inset 0 and `bar.frame.maxY == view.bounds.maxY − bar height` (i.e. resting position), and the list's `maxScrollExtent`/padding returns to its pre-gesture value.

Subjective, on the owner's iPhone (the bug report's own words are the spec):

1. **Open**: the bar rides up *with* the keyboard, no 1-frame gap at the top edge of the keyboard, no bounce at the end.
2. **Drag**: the bar and the list track the finger frame for frame; the list content does not shift relative to the bar.
3. **Release-cancel** (the reported failure): composer and list animate back *with* the keyboard's own curve; there is **no frame where the composer is gone/below the keyboard while the keyboard is still visible**, and the "few ms apart" double-image from the recording no longer occurs.
4. **Release-dismiss**: composer and list animate down together, composer ends above the home indicator, no flash behind the keyboard.
5. **Rapid repeated drags** (3-5 alternating, no pause): no accumulated offset, no stuck half-collapsed keyboard, no dead tracking (the composer must follow the finger on every drag), no leftover display link (O4).
6. **Reopen within ~300 ms of a dismiss**: the list is not shifted and the bar is back on the keyboard top.
7. Not regressed: the no-keyboard resting state (composer at the bottom, list padding correct), and the accessible/keyboard-hidden path on iPad floating keyboard (`KeyboardGeometry.isDockedBand`, `KeyboardManager.swift:253-257`).

---

## 5. Recommended order (time budget)

1. **30 min** — add §3C (CI runs the existing geometry suite). Trivial, protects what exists.
2. **2-3 h** — implement `CIKTrace` + hooks N1-N11 and the Dart metrics probe; run the **simulator** repro with the trace to shake out plumbing (this is where iteration is cheap).
3. **15 min** — owner runs the 4 gestures on `Worp`; returns the log (devicectl copy, §1.5).
4. **15 min** — read the trace against §1.6. This is the "confirm, don't guess" step; it should also settle whether candidate (e) (accessory VC stop) is live.
5. Fix → same trace, same gestures → §4 O1-O5 + the §3B check (or §3A if the fix stays small) → device checklist.

---

## 6. Risks / open questions

- **`--console` on a wireless device** can be flaky; the ring buffer + `devicectl copy from` is the fallback and is the reason to write the file rather than trust the console.
- **Uptalk is pinned to git `master`** (`pubspec.yaml:69-72`), so an instrumented run of the *real* app needs either a pushed branch or a temporary `dependency_overrides: cupertino_interactive_keyboard: {path: …}` + `flutter pub get` in uptalk (owner's call, one line, revertible). The plugin's own `example` needs nothing and reproduces the composer jump; start there and only move to uptalk if the *list* jump does not show up.
- **`physicalViewInsetBottom` read-back** uses a private selector; if a future engine renames it the log says `missing` once (`logMissingEngineAPI`, `KeyboardManager.swift:344-353`) instead of lying with 0.
- Adding a `Dictionary`-shaped log line per frame would be the one real cost; hence change-only + heartbeat + line cap. If profiling matters, build the line only when enabled (already the case) and keep `NSLog` (not `os_log` with `String(format:)` interpolation chains).
- The brief's architecture summary matched the code exactly; the only correction is that the swizzle is class-wide, so the second engine's `FlutterViewController` also feeds `KeyboardManager.willProcessKeyboardNotification` (candidate (e), §1.6). `ios/KeyboardGeometryTests` exists and `run.sh` works as the brief says.
