# Flutter layout / clip lane — what moves, what clips, and which layouts hide the seam

Task: task-2 (shared board). Date 2026-11-10. Read-only research; the only file written is this note.
Decision framed: choose the fix for the fast-drag list lag/clip, for the plugin owner, under the
constraints that the bar stays a live Flutter widget in the second engine, the main app keeps one
engine, and the interactive dismissal keeps its current feel.

Framework examined: local checkout Flutter 3.47.7, framework abaf9c523780a608bd46686fd5e53740a07077f8,
engine deb287481e3ce9468f3434937ced4240a70539ca
(/Users/vitekvitek/development/flutter/bin/cache/flutter.version.json). All framework line numbers
below are for that revision. The brief's suggested engine revision (d8a2d6c…) is not the local one; I
did not need engine source for this lane (that is task-1).

---

## 1. Verdict

The seam on the example screen is a layout artefact with exactly zero tolerance: with
Scaffold.resizeToAvoidBottomInset: true the body's height is screen − viewInsets.bottom, and the
example puts the accessory reservation in the same Column, so the list's viewport bottom edge is laid
out exactly at the native bar's top edge; the viewport then clips its children with Clip.hardEdge at
that moving edge. Any positive disagreement between the two producers — one scheduling hop of inset
transport, or one height-event hop of the reservation — opens a gap that the Scaffold background fills
(the band) and cuts a message at the clip line. Nothing in the app-side layout absorbs the
disagreement, so the app-side fix is not to make the two terms equal (you cannot, one of them crosses
a thread) but to get the clip line under an opaque surface that is a whole bar height behind it:
overscan the list behind the composer by at least the bar height, pad the content from the same
reserved value, and let the bar be the only thing the user sees moving.

## 2. Hypotheses — what this lane adds

| # | Hypothesis | Verdict from layout evidence |
|---|---|---|
| H1 | framework learns the inset one platform→UI task after the bar moves | Consistent, and sufficient. The layout has zero tolerance, so any positive transport lag becomes a visible band; the band's height is the lag. |
| H2 | per-frame Scaffold relayout drops frames | Not the mechanism. The body subtree is not rebuilt (identical widget instance, framework.dart:4027); rebuild set is {Scaffold, MediaQuery dependents on the padding/viewInsets aspects}; per frame there is one relayout of Scaffold layout + body Column + viewport. No dropped-frame evidence exists in the repo traces. |
| H3 | engine's own inset animation competes | Not during the drag (the driver invalidates it on the first write and keeps targetViewInsetBottom synced: KeyboardManager.swift:546-557, 602-646). Remains possible on the release animation only. |
| H4 | reserved height ≠ native bar height | Consistent but bounded and mostly benign. During a drag the reserve is constant (bar padding = 0 while the keyboard is up). The 34 pt safe-area term flips only at a transition boundary, and the harmful sign (reserve > bar) lasts only the height-event hop. Magnitude ≲ 34 pt at the boundary, a few pt mid-animation — cannot be the large fast-flick band. |
| H5 | UIKit's drag/guide sampling is late so even the bar lags | Cannot create the seam. The bar and the engine inset are computed from the same guide reading in the same call (KeyboardManager.swift:478-518); a late guide delays both, so it cancels. Only the transport of the two differs. |
| H6 | ordinary ListView clipping + debug jank, no timing bug | Half true, therefore wrong. The clipping is ordinary, but at rest the seam is exact (§3: R = h-bar, ī = i), so a static screenshot is clean; the artefact only exists while the two producers disagree, and its size scales with drag speed. Debug jank can add frames; it is not the cause. |

Surviving: H1 as the producer of the mismatch, amplified to a visible tear by a layout with no
overscan. H4 contributes a small second tick at the transition boundary; H5 is cancelled by shared
sourcing; H2/H3/H6 are not the mechanism.

## 3. Geometry, exactly

Screen coordinates, y down, S = Flutter view height.

| symbol | meaning | source |
|---|---|---|
| A | app bar height (68 + status bar here) | example/lib/keyboard_accessory.dart:125-154 |
| ī | engine viewInsets.bottom, logical px | plugin write KeyboardManager.swift:543-580; framework media_query.dart:309 |
| R | reserved accessory height in the Column (Tween-animated) | lib/src/cupertino_hosted_input_accessory.dart:139-149 |
| i | native bar inset from the view bottom, points | KeyboardManager.swift:509-518 |
| h-bar | native bar total height (contentHeight + contentPadding) | CIKHostedAccessoryBar.swift:60-76 |

Body height (resize true, no bottom widgets):
B = S − A − max(ī, bottomWidgetsHeight) — scaffold.dart:1088-1091, 1094, 1106-1114, with
minInsets.bottom = viewInsets.bottom (scaffold.dart:3220-3222).

* list viewport bottom = S − ī − R
* native bar top = S − i − h-bar
* gap = barTop − listBottom = (ī − i) + (R − h-bar)

Band height = max(0, gap); the gap lies outside the ListView box, inside the body Column, so it is
painted by the Scaffold's Material background (scaffold.dart:3236-3237) — i.e. the chat background,
which is why it reads as a tear rather than as a wrong colour (unless the app paints a wallpaper behind
the list). Clip line = the viewport box's bottom edge: the viewport pushes a clip rect Offset.zero &
size with Clip.hardEdge whenever it has visual overflow (rendering/viewport.dart:969-985; defaults
widgets/viewport.dart:79, widgets/scroll_view.dart:129).

Each term and what it produces:

1. (ī − i) transport hop. One frame of keyboard travel: a hard flick traverses ~336 pt in 150-250 ms
   → peak ~2000-3000 pt/s → 33-50 pt/frame at 60 Hz, 17-25 pt at 120 Hz. Produces the band directly,
   proportional to drag speed, plus the cut at the clip line. This is the term that matches "only when
   you drag fast".
2. (R − h-bar) reservation hop. R comes from a native height event → method channel → Dart setState →
   next frame (CIKHostedAccessoryBar.swift:145-153, CupertinoInteractiveKeyboardPlugin.swift:258-264,
   cupertino_hosted_input_accessory.dart:182-198), while h-bar changes inside UIView.animate/layout
   (KeyboardManager.swift:326-343). While the keyboard is up both are contentHeight (padding 0), so the
   term is 0 mid-drag; it opens only where contentPadding flips (34 pt, at a transition boundary) and
   settles within a hop or two. Sign matters: R > h-bar → band (bad); R < h-bar → content under the
   bar (invisible).
3. The 34 pt safe-area sweep. MediaQuery.padding.bottom goes 34 → 0 when the keyboard covers the home
   indicator, because padding is computed from viewPadding absorbed by viewInsets
   (bin/cache/pkg/sky_engine/lib/ui/window.dart:72-75; media_query.dart:307). This only affects the
   placeholder reserve ((_reportedHeight ?? height + padding.bottom), cupertino_hosted_input_accessory.dart:139-140)
   and is the 34 pt step already in the device addendum
   (docs/superpowers/specs/2026-11-10-hosted-bar-ownership-design.md:112-118).
4. Unit/rounding. Plugin writes physical px (KeyboardManager.swift:517), framework divides by DPR
   (media_query.dart:309) → sub-point, negligible.
5. A constant offset (not speed-proportional). barInsetAtDragStart = barInset (the last notification
   value) is paired with the first live guideTopAtDragStart (KeyboardManager.swift:217-236, 492-506).
   If those two disagree when tracking starts, the bias is constant for the whole drag. This is a
   falsifiable alternative to term 1: constant band vs speed-proportional band distinguishes them.
6. A silent no-op in the owner's attempted fix. With resizeToAvoidBottomInset: true the body's
   MediaQuery has viewInsets.bottom removed (scaffold.dart:2904-2934 + 3034), so app code inside the
   body that reads MediaQuery.viewInsetsOf(context).bottom for padding reads 0 — the padding was never
   applied. With resize: false the same read is non-zero, but the padding then re-creates exactly the
   moving edge the Scaffold had, fed by the same late value (§5.2).

Why a cut is possible at all: at scroll offset 0 a reverse list is anchored to its leading (bottom)
edge (scroll_view.dart:429-431; the reverse mapping of padding.bottom to the leading edge is
rendering/sliver_padding.dart:41-52), and the default adjustPositionForNewDimensions keeps the pixel
offset (scroll_physics.dart:356-371), so the content translates with the edge and the newest bubble
stays 8 pt clear of it. The cut appears when the content is not flush with the edge: the same fast
downward pan that drags the keyboard also drags/bounces the list (CIKScrollView.swift:18-21, 67-69
allows simultaneous recognition), i.e. exactly the fast-flick case, and the plugin's own physics
deliberately keeps pixels while scrolling (lib/src/interactive_keyboard_scroll_physics.dart:12-30).

## 4. What rebuilds / relayouts per keyboard frame (framework trace)

1. Plugin writes the engine metric from the platform thread (KeyboardManager.swift:543-580).
2. Metrics change → WidgetsBinding.handleMetricsChanged → observers' didChangeMetrics
   (widgets/binding.dart:922-927) → _MediaQueryFromViewState.didChangeMetrics → _updateData → setState
   if MediaQueryData.fromView differs (media_query.dart:2388-2411; data from view at
   media_query.dart:300-309). The root MediaQuery is installed by View (widgets/binding.dart:1628-1645).
3. Rebuild: Scaffold reads MediaQuery.paddingOf + viewInsetsOf in build (scaffold.dart:3220-3222) —
   aspect dependencies (media_query.dart:1276, 1841). A new _ScaffoldLayout with new minInsets makes
   shouldRelayout true (scaffold.dart:1299-1306).
4. The page's Column is the same widget instance, so updateChild returns early (framework.dart:4027):
   the list subtree is not rebuilt. _MessageBubble depends on MediaQuery.sizeOf only
   (example/lib/keyboard_accessory.dart:200-202), and size does not change → no row rebuilds.
5. Relayout: CustomMultiChildLayout lays the body out at maxHeight = B (scaffold.dart:1088-1114); the
   body Column's Expanded tightens the ListView; the viewport relayouts its visible slivers; the
   ScrollPosition applies new dimensions.
6. Paint: the viewport clips at the (new) box edge (rendering/viewport.dart:969-985); the accessory's
   TweenAnimationBuilder animates R only when a height event says so.

So the per-frame work is one Scaffold relayout pass — cheap — and H2's dropped-frame story has no
support. The coupling that matters is which value drives geometry (viewInsets), not the cost.

## 5. App-side layouts evaluated (rest / slow drag / fast flick / cost, risk)

The invariant every layout is judged by: the list's clip line must sit under the opaque composer (or a
static opaque surface) by more than the worst-case disagreement; nothing may be cut at a line that can
emerge outside an opaque surface.

### 5.1 Recommended — resize: true, full-bleed overscan, opaque backing band, no Column slot

Concretely, replacing the example's Column (example/lib/keyboard_accessory.dart:155-173):

    body: Stack(
      fit: StackFit.expand,
      children: [
        CupertinoInteractiveKeyboard(
          child: ValueListenableBuilder<double>(
            valueListenable: controller.barHeight, // new: the reported total height, see below
            builder: (_, barHeight, __) => ListView.builder(
              reverse: true,
              // Visual padding: for a reverse list bottom IS the leading edge
              // (rendering/sliver_padding.dart:41-52).
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0).copyWith(bottom: barHeight + 8),
              itemBuilder: ...,
            ),
          ),
        ),
        // Opaque backing for the whole bar band, incl. the home-indicator strip. It also hides
        // the list's clip line, which is now at the body bottom.
        ValueListenableBuilder<double>(
          valueListenable: controller.barHeight,
          builder: (_, barHeight, __) => Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(height: barHeight, width: double.infinity,
              child: ColoredBox(color: surface)),
          ),
        ),
        Align(alignment: Alignment.bottomCenter,
          child: CupertinoKeyboardAccessory(entrypoint: ..., libraryURI: ..., controller: controller)),
      ],
    )

The only plugin addition is exposing the already-computed total height (a ValueListenable<double> on
CupertinoHostedInputAccessoryController, fed from the same _handleEvent), and the widget no longer has
to reserve layout space (the "hidden bar still reserves" contract stays the default for other apps).

* At rest: pixel-identical to today — the backing band covers exactly the bar's rect, the composer is
  opaque over its content, the newest bubble is 8 pt above the composer, and the list's clip line is
  hidden behind the backing band.
* Slow drag: band 0 (the clip line is h-bar − lag below the bar's top, i.e. under opaque pixels for any
  lag < h-bar); content follows the finger; the residual is one frame of motion under a static edge.
* Fast flick: the same; a 30-50 pt/frame lag is absorbed by the ~52-100 pt of bar, the clip line never
  emerges, so no cut line and no band edge. The list still trails by one frame in motion — unavoidable
  app-side (the value itself is one hop late).
* Cost: ~one bar height of extra painted rows per frame (trivial); one extra setState per height event
  (already exists); the accessory no longer shrinks the list.
* Risks: (a) the dismiss-gesture arming rect is the list's layout rect reported from Flutter
  (rect_observer.dart:35-53, checked against the pan location in CIKScrollView.swift:53-65), so a
  full-bleed list makes the gesture armable from the composer strip — the plugin should inset the
  reported rect by the reserved height (or take a bottomIgnore); (b) the list's scroll extent now
  includes the hidden strip, so anything that assumes maxScrollExtent maps to visible pixels must use
  the content padding (the app's scroll-to-bottom uses the reverse anchor, fine); (c) a11y: semantics
  rects are unchanged for nodes because no node is padded into the strip.
* Optional native one-liner: setting CIKHostedAccessoryBar.backgroundColor (currently deliberately
  .clear, CupertinoInteractiveKeyboardPlugin.swift:222-229) instead of the Flutter backing band removes
  risks (b)/(c) entirely and makes the strip opaque for bounce content too.

### 5.2 resizeToAvoidBottomInset: false + bottom padding / animated padding — rejected

Mechanics: with resize false minInsets.bottom is 0 (scaffold.dart:3220-3222, 2779-2781), the body keeps
full height and the app must re-add viewInsets.bottom itself. AnimatedPadding(Duration.zero) (the real
app's pattern, ../uptalk/lib/view/chat/presentation/bottom_panel.dart:1420-1440) is a 1:1 mirror: same
per-frame relayout, same late value, same zero-tolerance edge — the band survives. Any non-zero
duration makes the list trail the composer by the animation (worse; and mid-animation the padding is
between the old and new value → a permanent gap). Also MediaQuery.paddingOf(...).bottom inside the body
still reports viewPadding − viewInsets = 0 while the keyboard is up, and minViewPadding no longer
suppresses the bottom padding, so safe-area maths double up (scaffold.dart:3226-3230, 2925-2927).
Rest: fine. Slow drag: band shrinks with speed as in 5.1 but has no overscan floor. Fast flick: same
band, plus an animation lag if animated. Verdict: structurally identical to the current screen; this is
why the owner's attempt changed nothing (and why, with resize: true, the padding read 0 — §3.6).

### 5.3 Transform.translate instead of relayout — not a primary fix

Mechanics: keep the body full height, translate the list's content up by ī; layout is unchanged
(RenderTransform is paint-only: rendering/proxy_box.dart:2530, 2735), the viewport's clip line is fixed
at the view bottom, i.e. behind the keyboard/composer, so no band and no cut is possible. At rest:
identical if the translation is ī and the bottom padding covers the composer. Slow drag / fast flick:
no band ever; the content trails by the same one hop, and no rows are revealed — the reason the project
rejected this in 6dc5869
(docs/superpowers/specs/2026-11-09-keyboard-accessory-sync-design.md:55-56). Cost/risk: scroll extent
and semantics keep the keyboard-covered region; the reserve has to become a constant/animated bottom
padding (reintroducing a term, but only for content offset, not for a clip line); RectObserver reports
a static rect, so drag tracking sees no viewport change (interactive_keyboard_scroll_physics stops
mattering). Useful only as an emergency mode.

### 5.4 Decouple content from the inset (fixed list, keyboard covers it) — rejected for a chat

Mechanics: the list never resizes; the keyboard/bar covers the bottom. At rest: unchanged. Slow drag /
fast flick: nothing moves, so no artefact at all — but the newest messages (and, depending on the
layout, the composer's own space) are covered while typing. To keep them visible you must reserve a
keyboard-height band, which leaves a permanent ~336 pt gap when the keyboard is closed, or animate it
as the keyboard moves — back to a two-producer race. Also fails the stated product requirement that the
content is revealed as the keyboard leaves
(docs/superpowers/specs/2026-11-09-keyboard-accessory-sync-design.md:30-36).

### 5.5 Custom scroll view / keyboard-aware wrapper (reserve as scroll content) — rejected (YAGNI)

Mechanics: put the reserve inside the scrollable (CustomScrollView with a SliverPadding or a trailing
SliverToBoxAdapter sized to the bar). At rest / drags: same as 5.1 if padded correctly, but the reserve
becomes scroll extent: when the composer grows, maxScrollExtent changes and, if the position is at the
end, the position is clamped (scroll_physics.dart:577-650 only maintains overscroll, not the end
anchor) → a visible jump on composer growth; the reserve can scroll away (not what a composer band
means); the arming rect grows further. Higher cost, same benefit as 5.1.

### 5.6 Consumer-app cross-check (the real scene, outside this repo)

The real app already implements the overscan family and its own comment states this exact failure mode:
"Without it the clip ends where the control starts… that line slices whatever paints above it"
(../uptalk/lib/ui/widgets/layout/bottom_overlap_viewport.dart:1-16), with the viewport laid out overlap
pixels taller via OverflowBox + a ClipRect (:32-50). But it overscans by only
_listOverlap = _composerHeight / 2
(../uptalk/lib/view/chat/presentation/direct_chat_page_state.dart:213) and pads the content by
restGap + _listOverlap (:223), used at
../uptalk/lib/view/chat/presentation/direct_chat_page_body.dart:205-227. Half a composer (~26-43 pt) is
smaller than a fast flick's per-frame travel (33-50 pt at 60 Hz) → prediction: the artefact appears
exactly when the drag exceeds ~composerHeight/2 per frame, i.e. only on fast flicks, and the cut line
emerges from under the composer's top edge. This is the cheapest natural experiment the owner has:
raise the overlap to the full reserve (or h-bar) and slow/fast drags should both be clean.

## 6. Evidence table

| id | type | locator | credibility | what it proves |
|---|---|---|---|---|
| E1 | file read (framework) | packages/flutter/lib/src/material/scaffold.dart:1088-1114, 3220-3222 @ 3.47.7 | high — exact SDK checkout; only the engine's own metrics write is in question | body height = screen − appBar − viewInsets.bottom; the list's bottom edge is geometry ticked directly by the engine inset. |
| E2 | file read (repo) | example/lib/keyboard_accessory.dart:155-173 + lib/src/cupertino_hosted_input_accessory.dart:139-149 | high — the code under test | the accessory reservation is a Column sibling, so at rest the list's bottom edge is exactly the bar's top edge: zero tolerance. |
| E3 | file read (framework) | packages/flutter/lib/src/rendering/viewport.dart:969-985; defaults widgets/viewport.dart:79, widgets/scroll_view.dart:129 | high | the "cut line" is the viewport box's bottom edge clipped with Clip.hardEdge; it moves with the layout, not with the composer. |
| E4 | file read (repo) | ios/.../KeyboardManager.swift:478-518, 543-580 | high | one value drives both the bar (same runloop turn, layoutIfNeeded) and the engine inset → the disagreement is transport, not two different sources; rules out H5 as a cause. |
| E5 | file read (repo) | lib/src/cupertino_hosted_input_accessory.dart:182-198; CIKHostedAccessoryBar.swift:145-153; KeyboardManager.swift:326-343 | high | the reserved height is event-driven (channel → setState → next frame) while the bar's height animates in UIKit: a second, bounded mismatch term (H4). |
| E6 | file read (framework) | packages/flutter/lib/src/material/scaffold.dart:2904-2934, 3034 | high | inside the body of a resizeToAvoidBottomInset: true Scaffold, viewInsets.bottom is 0 → an in-body bottom-padding fix silently does nothing. |
| E7 | file read (framework) | widgets/media_query.dart:2388-2411; widgets/binding.dart:922-927 | high — proves the hop exists somewhere, not its exact length | new insets are delivered through didChangeMetrics → setState; the layout of a new value cannot precede that callback. |
| E8 | document (repo design note) | docs/superpowers/specs/2026-11-09-keyboard-accessory-sync-design.md:18-21, 55-56 | medium — internal analysis, no measurement in-tree | the project's own analysis: a display-link inset write is one frame late (engine vsync first), and a transform-only approach freezes the content. |
| E9 | document (repo, device trace quoted) | docs/superpowers/specs/2026-11-10-hosted-bar-ownership-design.md:112-128 | medium-high — device log quoted, not reproducible here | on device the reserved height stepped 34 pt and an instant hide wrote the inset in one frame; both are reserve/inset discontinuities, and both are now interpolated — i.e. the remaining artefact should be the small, continuous term. |
| E10 | file read (consumer app, read-only) | ../uptalk/lib/ui/widgets/layout/bottom_overlap_viewport.dart:1-76; .../direct_chat_page_body.dart:205-227; .../direct_chat_page_state.dart:213,223 | medium — app repo, may drift from the shipping build | the real app already overscans behind the composer but only by composerHeight/2, and documents this exact clip-line failure → the natural experiment and a size bound. |
| E11 | file read (repo + framework) | lib/src/interactive_keyboard_scroll_physics.dart:12-30; widgets/scroll_physics.dart:356-371 | high | the pixel offset is preserved across viewport resize (especially while scrolling) — the content does not "catch up" to the moving edge by itself. |
| E12 | file read (framework) | widgets/framework.dart:4027; media_query.dart:1276, 1841 | high | identical body widget instance across the Scaffold rebuild → per-frame cost is one relayout, no row rebuilds → H2 unsupported. |
| E13 | file read (repo) | lib/src/rect_observer.dart:35-53; CIKScrollView.swift:53-65; CupertinoInteractiveKeyboardPlugin.swift:69-73 | high | the interactive-dismissal arming region is the list's layout rect → any layout that extends the list behind the bar also extends where a dismiss gesture can start (feel risk of 5.1). |
| E14 | file read (repo) | CupertinoInteractiveKeyboardPlugin.swift:222-229; CIKHostedAccessoryBar.swift:121-132 | high | the bar is deliberately transparent and the hosted view is pinned to its top at content height only → the home-indicator strip is not painted by the accessory; overscan needs a Flutter backing band (or an opaque bar). |

Locator conventions: path:line; framework paths are relative to
/Users/vitekvitek/development/flutter/packages/flutter/lib/src/; ../uptalk/… is the consumer app repo,
read-only and outside this working tree; URLs/access dates are in the web-research lane notes.

## 7. Ruled out

* H2 (per-frame Scaffold relayout cost / dropped frames) — the body subtree is not rebuilt (E12), the
  per-frame work is one relayout, and no trace in the repo shows dropped frames. Cost is not the
  driver; coupling is.
* H6 as a complete explanation — at rest the seam is exact (E2), so the artefact requires a
  disagreement and scales with speed (E8, E10); plain clipping would look identical at all speeds.
* H5 as an independent cause — the bar and the inset are computed from the same guide reading in the
  same call (E4); a late guide delays both and cancels.
* H4 as the main cause — bounded by the 34 pt safe-area flip and a channel hop, and mostly in the
  benign sign (reserve smaller than the bar) during a drag (E5, E9). It is a contributor at transition
  boundaries, not the fast-flick band.
* resize:false + padding, and transform-only, as primary fixes — §5.2/§5.3: the first re-creates the
  same edge; the second stops revealing content (documented rejection).
* The owner's in-body padding attempt — reads 0 at that point in the tree (E6): the attempt could not
  have worked, independent of any timing.

## 8. The one critical evidence item

E2 + E1 together: the framework lays the body out at exactly screen − viewInsets.bottom
(scaffold.dart:1088-1114, 3220-3222) and the example places the accessory reservation as a Column
sibling (example/lib/keyboard_accessory.dart:155-173, cupertino_hosted_input_accessory.dart:139-149).
Therefore gap = (ī − i) + (R − h-bar) with no other term, and the clip line is the seam itself
(rendering/viewport.dart:969-985). If the layout had even one bar height of overscan, the same lag
would be invisible. That converts the question from "can the two clocks be made equal?" (they cannot
app-side, because one value crosses a thread) to "is the moving edge exposed?" — which is answerable and
fixable app-side today. If that item were wrong — i.e. if the list's edge were already under the
composer — then the band would have to come from the reserve/bar disagreement or a bug in the driver's
seeding, and the fix would move to the native lane.

## 9. Widget test that fails for the recommended layout (pure widget test, no device)

With the existing mock (test/mock_cupertino_interactive_keyboard.dart, pattern from
test/hosted_input_accessory_test.dart:21-57), pump the chat screen at iOS with a keyboard inset and a
reported bar height, then assert the seam invariant:

    testWidgets('list overscans the accessory band and keeps content clear of it',
        (tester) async {
      await tester.pumpWidget(chatScreen(viewInsetsBottom: 336, surface: Colors.white));
      await tester.pump();
      await pluginEmit(tester, {'type': 'height', 'height': 98.5});   // native bar total

      final list = tester.getRect(find.byType(ListView));
      final band = tester.getRect(find.byKey(const ValueKey('accessory-band'))); // backing band
      final listWidget = tester.widget<ListView>(find.byType(ListView));
      final padding = listWidget.padding! as EdgeInsets;

      // 1) the viewport reaches the body bottom (the band's bottom): it overscans the reserve
      expect(list.bottom, closeTo(band.bottom, 0.5));
      // 2) and the band is a whole bar tall, so one frame of lag cannot expose the clip line
      expect(band.height, greaterThanOrEqualTo(96));
      // 3) content is padded from the same reserved height, so no bubble sits at the clip line
      expect(padding.bottom, greaterThanOrEqualTo(98.5));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

On today's Column layout, assertion (1) fails by the reserved height (~98 pt): the list's bottom is the
band's top, not its bottom. That is exactly the missing overscan. Assertions (2)/(3) pin the
recommendation so a "reserve less but pad more" regression cannot sneak back.

## 10. Confidence and what would flip it

* High that the clip line is the viewport's box edge and that the example's seam has zero tolerance
  (framework source, E1-E3).
* High that the reserve is a second, event-driven producer and that the owner's in-body padding read 0
  (E5, E6).
* Medium-high that overscan of at least one bar height removes the visible tear regardless of which
  producer wins the frame (geometry is definitive; the residual is only one frame of motion, which no
  app-side layout can remove).
* Medium on which mismatch term dominates the observed band, because the only device evidence is a
  quoted trace (E9), not a per-frame inset log. What would flip it: a device trace of
  MediaQuery.viewInsetsOf(...) per frame during a fast drag. If the largest single-frame delta during a
  fast flick is ≤ ~3 pt, H1 is not the producer and the band must be the reserve term (H4) or the
  drag-start seeding offset (§3.5); if the band is constant rather than speed-proportional, it is the
  seeding offset, not transport. Either way the app-side remedy stays the same (hide the moving edge),
  but the plugin owner would additionally fix the driver bias.
