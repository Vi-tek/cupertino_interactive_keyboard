import Flutter
import QuartzCore
import UIKit

class KeyboardManager {
  static let shared = KeyboardManager()
  private static let handledUserInfoKey = "KeyboardManagerHandledUserInfoKey"

  var activeScrollViews = Set<CIKScrollView>()
  var activeInputAccessoryViews = Set<CIKInputAccessoryView>()

  weak var flutterViewController: FlutterViewController?

  /// The hosted accessory bar, when the Dart side uses one. The plugin positions it itself: its
  /// bottom edge is the keyboard's top edge while the keyboard is on screen and the view's bottom
  /// edge once it is gone, so the same inset formula keeps the content glued to it either way.
  weak var hostedAccessoryBar: CIKHostedAccessoryBar?

  /// The bar's bottom edge in points above the Flutter view's bottom, as last set by a keyboard
  /// notification. Read when a bar is created while the keyboard is already open.
  var currentBarInset: CGFloat { barInset }

  private(set) var barInset: CGFloat = 0
  private var barInsetAtDragStart: CGFloat = 0
  private var guideTopAtDragStart: CGFloat?
  private var interactiveTrackingDisplayLink: CADisplayLink?
  private var isInsetSyncScheduled = false
  private var lastReportedInset: CGFloat?
  private var lastBandBottom: CGFloat?
  private var staticTicks = 0
  private var trackingTicks = 0
  private var missingBandTicks = 0
  private var invalidatedEngineAnimation = false

  private init() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(interactiveDismissalDidChange),
      name: UIResponder.keyboardInteractiveDismissalNotification,
      object: nil
    )
  }

  func adjustKeyboardNotification(_ notification: Notification) -> Notification {
    lazy var maxInputAccessoryHeight = activeInputAccessoryViews.map(\.intrinsicContentSize.height).max() ?? 0

    guard
      var userInfo = notification.userInfo,
      !((userInfo[KeyboardManager.handledUserInfoKey] as? Bool) ?? false),
      maxInputAccessoryHeight > 0
    else {
      return notification
    }

    func adjustRect(_ value: NSValue) -> NSValue {
      var rect = value.cgRectValue
      rect.origin.y += maxInputAccessoryHeight
      rect.size.height -= maxInputAccessoryHeight
      return NSValue(cgRect: rect)
    }

    userInfo[KeyboardManager.handledUserInfoKey] = true
    userInfo[UIResponder.keyboardFrameBeginUserInfoKey] = userInfo[UIResponder.keyboardFrameBeginUserInfoKey]
      .flatMap({ $0 as? NSValue }).map(adjustRect)
    userInfo[UIResponder.keyboardFrameEndUserInfoKey] = userInfo[UIResponder.keyboardFrameEndUserInfoKey]
      .flatMap({ $0 as? NSValue }).map(adjustRect)

    return Notification(name: notification.name, object: notification.object, userInfo: userInfo)
  }

  /// Whether the interactive drag is currently driving the inset.
  var isTrackingKeyboard: Bool { interactiveTrackingDisplayLink != nil }

  /// Called on the main thread when the interactive drag starts and when it is released.
  var onKeyboardDraggingChanged: ((Bool) -> Void)?
  private var reportedKeyboardDragging = false
  private var bandBottomAtDragStart: CGFloat?

  /// Publishes the drag state to Dart, once per transition.
  ///
  /// A drag starts when the keyboard first follows the finger and ends when the finger is lifted:
  /// the tracking can outlive the gesture while the keyboard animates back into place.
  private func reportKeyboardDragging(_ dragging: Bool) {
    guard reportedKeyboardDragging != dragging else { return }
    reportedKeyboardDragging = dragging
    onKeyboardDraggingChanged?(dragging)
  }

  /// Reports the drag as started once the keyboard actually follows the finger.
  ///
  /// A scroll over the interactive area starts the tracking too, but leaves the keyboard where it
  /// is; the drag begins when the keyboard leaves the position it had when the tracking started.
  private func reportKeyboardDraggingIfMoved(_ bandBottom: CGFloat?) {
    guard let bandBottom else { return }
    guard let bandBottomAtDragStart else {
      self.bandBottomAtDragStart = bandBottom
      return
    }
    guard isDraggingKeyboard, abs(bandBottom - bandBottomAtDragStart) > 0.5 else { return }
    reportKeyboardDragging(true)
  }

  // MARK: - Interactive dismissal

  /// Whether the user is currently dragging the keyboard away.
  private var isDraggingKeyboard: Bool {
    activeScrollViews.contains {
      let state = $0.panGestureRecognizer.state
      return state == .began || state == .changed
    }
  }

  /// Called from the swizzled keyboard notification handlers before the engine processes them.
  ///
  /// The frame changes posted while the keyboard is dragged carry an empty frame, so a notification
  /// here ends the gesture (or changes the keyboard for another reason): the plugin stops driving
  /// the inset and the engine animates the release from the last inset the plugin wrote, with the
  /// keyboard's own curve.
  ///
  /// The band is deliberately not read here. UIKit may already have moved it to the resting
  /// position it is about to animate to, and writing that position would snap the content to the
  /// end of the release instead of animating it.
  ///
  /// The notifications the engine ignores are ignored here too, so a zero-frame change posted
  /// while the keyboard is dragged cannot stop the tracking and freeze the inset.
  func willProcessKeyboardNotification(_ notification: Notification?) {
    guard let notification else { return }
    // Every notification is traced, including the ones the engine ignores: the empty release frames
    // posted while the keyboard is dragged are what the trace has to rule out.
    traceNotificationIfNeeded(notification)
    guard !isIgnoredByEngine(notification) else { return }
    stopInteractiveTracking()
  }

  /// Logs the notification the engine is about to handle.
  ///
  /// Every release notification is traced, not only the changing ones: the duration and the end
  /// frame are what decide whether the engine animates the inset or snaps it.
  private func traceNotificationIfNeeded(_ notification: Notification) {
    guard CIKTrace.isEnabled else { return }
    let info = notification.userInfo
    let begin = (info?[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue)?.cgRectValue
    let end = (info?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
    let duration = (info?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue
    let curve = (info?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue
    let isLocal = (info?[UIResponder.keyboardIsLocalUserInfoKey] as? NSNumber)?.boolValue
    CIKTrace.log(
      "keyboard",
      "name=\(notification.name.rawValue) begin=\(CIKTrace.rect(begin)) end=\(CIKTrace.rect(end)) duration=\(duration.map(CIKTrace.seconds) ?? "nil") curve=\(curve.map(String.init(describing:)) ?? "nil") isLocal=\(isLocal.map(String.init(describing:)) ?? "nil") tracking=\(isTrackingKeyboard) dragging=\(isDraggingKeyboard)"
    )
  }

  /// Whether the engine would ignore this notification.
  ///
  /// Mirrors the filter of the engine's keyboard inset manager: a frame change with an empty frame
  /// is posted while the keyboard is dragged, and a notification that is not local belongs to
  /// another app or view controller.
  private func isIgnoredByEngine(_ notification: Notification) -> Bool {
    // The engine always handles hide notifications.
    guard notification.name != UIResponder.keyboardWillHideNotification else { return false }

    let info = notification.userInfo
    if let isLocal = info?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool, !isLocal {
      return true
    }
    guard notification.name == UIResponder.keyboardWillChangeFrameNotification else { return false }
    // Only an exactly zero frame is posted while the keyboard is dragged; an empty frame with a
    // position can be a multitasking switch, which the engine does handle.
    let frame = (info?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
    return frame == .zero
  }

  /// Starts live keyboard tracking if a keyboard accessory view is currently on screen.
  ///
  /// Called when the dismissal gesture begins, so tracking starts before the keyboard moves.
  func startTrackingIfKeyboardVisible() {
    if activeInputAccessoryViews.contains(where: { $0.window != nil }) {
      startInteractiveTracking()
      return
    }

    // The hosted bar is on screen whenever the plugin is used, so it only marks a visible keyboard
    // once its bottom edge has left the Flutter view's bottom edge.
    guard
      let hostedAccessoryBar,
      hostedAccessoryBar.window != nil,
      let flutterView = flutterViewController?.view,
      flutterView.window != nil,
      flutterView.bounds.maxY - hostedAccessoryBar.convert(hostedAccessoryBar.bounds, to: flutterView).maxY > 1
    else {
      return
    }

    startInteractiveTracking()
  }

  /// Called from the pan gesture on every `.began` / `.changed`.
  ///
  /// UIKit applies the drag after the touch is delivered; the inset is written on the next main
  /// runloop turn so it sees the position UIKit just applied, and still lands before the next
  /// vsync — a write from the display link would miss the frame that is already starting.
  func keyboardDragDidChange() {
    guard interactiveTrackingDisplayLink != nil else { return }
    // UIKit has normally already applied the drag by the time the gesture action runs, so the
    // position is written here as well: a write from the deferred block below can miss the frame
    // that is about to start, and the missed frame is the visible correction at the start of a
    // drag.
    reportKeyboardDraggingIfMoved(syncInset())
    guard !isInsetSyncScheduled else { return }
    isInsetSyncScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.isInsetSyncScheduled = false
      // The gesture may have ended before this turn: the engine already took the inset over.
      guard self.interactiveTrackingDisplayLink != nil else { return }
      self.syncInset()
    }
  }

  /// Called from the pan gesture when the finger is lifted.
  ///
  /// The tracking can outlive the gesture while the keyboard animates back into place, so the drag
  /// state ends with the gesture, not with the tracking.
  func keyboardDragDidEnd() {
    reportKeyboardDragging(false)
  }

  /// Seeds the bar inset when the bar is created while the keyboard is already open, so the first
  /// drag frame does not drive the content from zero.
  func trackBarInset(_ inset: CGFloat) {
    barInset = inset
  }

  /// Stops a running keyboard animation on the bar and pins it where it is currently drawn.
  ///
  /// A drag can begin while the keyboard is still animating. Taking over from the animation's end
  /// target would snap the Flutter content to the end of that animation while the bar is still
  /// travelling.
  private func freezeBarAtVisiblePosition() {
    guard let bar = hostedAccessoryBar, let superview = bar.superview else { return }
    let frame = bar.layer.presentation()?.frame ?? bar.layer.frame
    let visibleInset = max(0, superview.bounds.maxY - frame.maxY)
    bar.layer.removeAllAnimations()
    bar.setBottomInset(visibleInset)
    if visibleInset > 0.5 {
      bar.contentPadding = 0
    }
    UIView.performWithoutAnimation {
      superview.layoutIfNeeded()
    }
    barInset = visibleInset
  }

  private func startInteractiveTracking() {
    guard interactiveTrackingDisplayLink == nil else { return }
    ownedHideLink?.invalidate()
    ownedHideLink = nil
    freezeBarAtVisiblePosition()
    barInsetAtDragStart = barInset
    guideTopAtDragStart = guideTopInView()
    lastReportedInset = nil
    lastBandBottom = nil
    staticTicks = 0
    trackingTicks = 0
    missingBandTicks = 0
    isInsetSyncScheduled = false
    invalidatedEngineAnimation = false
    bandBottomAtDragStart = nil

    let displayLink = CADisplayLink(target: self, selector: #selector(trackInteractiveKeyboard))
    displayLink.add(to: .main, forMode: .common)
    interactiveTrackingDisplayLink = displayLink
    CIKTrace.log("tracking", "start")
  }

  func stopInteractiveTracking() {
    if isTrackingKeyboard {
      CIKTrace.log("tracking", "stop band=\(CIKTrace.points(lastBandBottom))")
    }
    interactiveTrackingDisplayLink?.invalidate()
    interactiveTrackingDisplayLink = nil
    guideTopAtDragStart = nil
    lastReportedInset = nil
    staticTicks = 0
    trackingTicks = 0
    missingBandTicks = 0
    isInsetSyncScheduled = false
    invalidatedEngineAnimation = false
    reportKeyboardDragging(false)
  }

  /// Moves the bar onto the keyboard's end position for a keyboard notification.
  ///
  /// The bar is not constrained to the keyboard layout guide: the guide follows the drag but snaps to
  /// its end position on release, so the plugin moves the bar itself, with the notification's own
  /// duration and curve. The engine keeps animating the Flutter inset, so nothing is written to it
  /// here.
  func keyboardNotificationHandled(_ notification: Notification, wasTracking: Bool) {
    guard !isIgnoredByEngine(notification) else { return }
    // UIKit can post the release notification while the dismissal recognizer is still in its
    // begin/changed phase. One runloop turn later the gesture is over.
    if wasTracking, isDraggingKeyboard {
      CIKTrace.log(
        "release",
        "deferred: still dragging notification=" + notification.name.rawValue
      )
      DispatchQueue.main.async { [weak self] in
        self?.applyKeyboardNotification(notification)
      }
      return
    }
    applyKeyboardNotification(notification)
  }

  /// The bar inset a keyboard notification ends at, or nil when the view is not usable.
  private func hostedTargetInset(_ notification: Notification) -> (points: CGFloat, hidden: Bool)? {
    guard
      let flutterViewController,
      let flutterView = flutterViewController.view,
      let window = flutterView.window
    else {
      return nil
    }
    guard
      let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?
        .cgRectValue
    else {
      return nil
    }
    let viewRect = liveScreenRect(of: flutterView, in: window.screen)
    // A hidden, empty or floating keyboard leaves no band, so the bar belongs at the view's bottom.
    let hidden =
      notification.name == UIResponder.keyboardWillHideNotification
      || endFrame.isEmpty
      || !KeyboardGeometry.isDockedBand(bandWidth: endFrame.width, viewWidth: viewRect.width)
    let bandBottom =
      KeyboardGeometry.releaseBandBottom(
        keyboardTop: hidden ? nil : endFrame.minY,
        viewBottom: viewRect.maxY
      ) - viewRect.minY
    return (KeyboardGeometry.barInset(bandBottom: bandBottom, viewHeight: viewRect.height), hidden)
  }

  private func applyKeyboardNotification(_ notification: Notification) {
    guard let target = hostedTargetInset(notification) else { return }
    let info = notification.userInfo
    let duration =
      (info?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
    let curve = (info?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 7
    let targetInset = target.points
    let includesSafeArea = targetInset <= 0.5
    barInset = targetInset
    CIKTrace.log(
      "keyboard",
      "bar target=" + CIKTrace.points(targetInset)
        + " duration=" + CIKTrace.seconds(duration)
        + " curve=" + String(curve)
        + " includesSafeArea=" + String(includesSafeArea)
    )

    guard let bar = hostedAccessoryBar, bar.window != nil else { return }
    // The bottom moves with the notification's own animation; the padding is part of the same
    // motion so the composer lands above the home indicator instead of being pushed up later.
    let targetPadding = includesSafeArea ? bar.restingPadding : 0
    if abs(bar.contentPadding - targetPadding) > 0.05 {
      bar.heightAnimation = (max(duration, 0.2), curve)
    }
    let animations = {
      bar.setBottomInset(targetInset)
      bar.contentPadding = targetPadding
      bar.superview?.layoutIfNeeded()
    }
    if duration > 0 {
      UIView.animate(
        withDuration: duration,
        delay: 0,
        options: UIView.AnimationOptions(rawValue: curve << 16),
        animations: animations
      )
    } else {
      UIView.performWithoutAnimation(animations)
    }
  }

  // MARK: - Instant hides

  private var ownedHideLink: CADisplayLink?
  private var ownedHideStartInset: CGFloat = 0
  private var ownedHideTargetInset: CGFloat = 0
  private var ownedHideStartTime: CFTimeInterval = 0
  private var ownedHidePadding: CGFloat?
  private let ownedHideDuration: Double = 0.25

  /// Whether the plugin should run a collapsing transition itself instead of letting the engine take it.
  ///
  /// A notification with a zero duration makes the engine write the end inset in one frame (its
  /// "hide immediately" path for a zero-duration hide, and a zero-length animation for a frame
  /// change). While the keyboard still animates away that snaps the whole app content by the
  /// keyboard height, so the plugin animates the inset down itself for any instant collapse.
  func ownsInstantCollapse(_ notification: Notification) -> Bool {
    guard hostedAccessoryBar != nil, !isIgnoredByEngine(notification) else { return false }
    let duration =
      (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?
      .doubleValue ?? 0
    guard duration <= 0 else { return false }
    guard let target = hostedTargetInset(notification), let window = hostedAccessoryBar?.window
    else {
      return false
    }
    let current = (readPhysicalViewInsetBottom() ?? 0) / window.screen.scale
    return target.points < current - 1
  }

  /// Takes the inset down to the notification's target over the keyboard's usual duration, with the
  /// padding growing over the last 34 pt so the composer settles without a late push.
  ///
  /// Both Flutter view controllers see the notification; only the first one runs the transition.
  func ownedCollapseTransition(_ notification: Notification) {
    guard ownedHideLink == nil else { return }
    guard let target = hostedTargetInset(notification), let bar = hostedAccessoryBar,
      let window = bar.window
    else {
      return
    }
    let current = (readPhysicalViewInsetBottom() ?? 0) / window.screen.scale
    guard current > target.points + 1 else { return }
    invalidateEngineAnimation()
    ownedHideLink?.invalidate()
    ownedHideStartInset = current
    ownedHideTargetInset = target.points
    ownedHideStartTime = CACurrentMediaTime()
    ownedHidePadding = bar.restingPadding
    let link = CADisplayLink(target: self, selector: #selector(tickOwnedCollapse))
    link.add(to: .main, forMode: .common)
    ownedHideLink = link
  }

  @objc
  private func tickOwnedCollapse() {
    guard let bar = hostedAccessoryBar, let flutterView = bar.superview else {
      ownedHideLink?.invalidate()
      ownedHideLink = nil
      return
    }
    let t = min(1, max(0, (CACurrentMediaTime() - ownedHideStartTime) / ownedHideDuration))
    let eased = t * t * (3 - 2 * t)
    let inset = ownedHideStartInset + (ownedHideTargetInset - ownedHideStartInset) * eased
    let padding = max(0, (ownedHidePadding ?? 0) - inset)
    barInset = inset
    bar.setBottomInset(inset)
    bar.contentPadding = padding
    UIView.performWithoutAnimation {
      flutterView.layoutIfNeeded()
    }
    publishInset(inset * (bar.window?.screen.scale ?? 1))
    guard t >= 1 else { return }
    ownedHideLink?.invalidate()
    ownedHideLink = nil
    barInset = ownedHideTargetInset
    bar.setBottomInset(ownedHideTargetInset)
    bar.contentPadding = max(0, (ownedHidePadding ?? 0) - ownedHideTargetInset)
    ownedHidePadding = nil
  }

  /// The keyboard layout guide's top in the Flutter view's coordinates, while it is live.
  ///
  /// It is only used as a delta source during an interactive drag, never as the bar's position.
  private func guideTopInView() -> CGFloat? {
    guard #available(iOS 15.0, *), let flutterView = flutterViewController?.view else { return nil }
    let frame = flutterView.keyboardLayoutGuide.layoutFrame
    // A laid-out guide spans the view's width; a zero frame means it has not been laid out yet.
    return frame.width > 0 && frame.minY >= 0 && frame.minY.isFinite ? frame.minY : nil
  }

  @objc
  private func interactiveDismissalDidChange() {
    startTrackingIfKeyboardVisible()
  }

  @objc
  private func trackInteractiveKeyboard() {
    trackingTicks += 1
    let bandBottom = syncInset()
    reportKeyboardDraggingIfMoved(bandBottom)
    traceInteractiveFrame()

    // The band left the screen: there is nothing left to follow.
    missingBandTicks = bandBottom == nil ? missingBandTicks + 1 : 0
    if missingBandTicks >= 5 {
      stopInteractiveTracking()
      return
    }

    let hasStoppedMoving = bandBottom != nil && bandBottom == lastBandBottom
    lastBandBottom = bandBottom
    staticTicks = hasStoppedMoving ? staticTicks + 1 : 0

    // The tracking ends once the keyboard came to rest. While the keyboard keeps moving, either
    // because it is dragged or because it animates back into place, the plugin stays in charge of
    // the inset.
    let hasSettled = KeyboardGeometry.shouldStopTracking(
      isDragging: isDraggingKeyboard,
      hasStoppedMoving: hasStoppedMoving,
      staticTicks: staticTicks
    )
    if hasSettled || (trackingTicks > 600 && !isDraggingKeyboard) {
      stopInteractiveTracking()
    }
  }

  /// Drives the bar and the engine inset while the keyboard is dragged.
  ///
  /// The plugin owns the bar's position, so the keyboard layout guide is only used as a live *delta*
  /// since the drag started: a guide that is stale before the drag cannot offset the bar or the
  /// inset. The same computed inset moves both, so they cannot disagree.
  ///
  /// - Returns: The bottom edge of the keyboard band in screen coordinates, for the settle detection.
  @discardableResult
  private func syncInset() -> CGFloat? {
    guard
      let flutterViewController,
      let flutterView = flutterViewController.view,
      let window = flutterView.window
    else {
      return nil
    }
    let screen = window.screen
    let viewRect = liveScreenRect(of: flutterView, in: screen)

    if let bar = hostedAccessoryBar, bar.window != nil {
      // The guide may not have been laid out when the drag started; take its first live reading as
      // the start instead of freezing the drag.
      if guideTopAtDragStart == nil, let guide = guideTopInView() {
        barInsetAtDragStart = barInset
        guideTopAtDragStart = guide
      }
      let inset: CGFloat
      if let guideAtStart = guideTopAtDragStart, let guideNow = guideTopInView() {
        inset = KeyboardGeometry.dragBarInset(
          insetAtStart: barInsetAtDragStart,
          guideTopAtStart: guideAtStart,
          guideTop: guideNow,
          maxInset: viewRect.height
        )
      } else {
        inset = barInset
      }
      // The content lifts out of the home-indicator strip as the bar reaches the bottom, instead of
      // being pushed up after the keyboard is gone.
      let padding = max(0, bar.restingPadding - inset)
      if abs(inset - barInset) > 0.5 || abs(padding - bar.contentPadding) > 0.5 {
        barInset = inset
        bar.setBottomInset(inset)
        bar.contentPadding = padding
        // Lay out now so the frame that is about to render already has the bar in place.
        bar.superview?.layoutIfNeeded()
      }
      publishInset(inset * screen.scale)
      return viewRect.maxY - inset
    }

    // Classic path: the plugin's input accessory view is the band.
    guard let accessoryView = activeInputAccessoryViews.first(where: { $0.window != nil }) else {
      return nil
    }
    let bandRect = liveScreenRect(of: accessoryView, in: screen)
    // A floating keyboard has no inset in the engine, so it must not be driven here either.
    guard KeyboardGeometry.isDockedBand(bandWidth: bandRect.width, viewWidth: viewRect.width)
    else {
      return nil
    }
    let bandBottom = bandRect.maxY
    publishInset(
      KeyboardGeometry.inset(
        bandBottom: bandBottom,
        viewBottom: viewRect.maxY,
        scale: screen.scale
      )
    )
    return bandBottom
  }

  /// Logs one pacing line per display-link tick while the keyboard is dragged.
  ///
  /// The native half of the probe: what the engine has, what the bar is drawn at, and where the
  /// guide is. Pair it with the Dart "metrics" line to see the frame the list is laid out in.
  private func traceInteractiveFrame() {
    guard hostedAccessoryBar?.window != nil else { return }
    let refresh = interactiveTrackingDisplayLink.map { $0.targetTimestamp - $0.timestamp } ?? 0
    CIKTrace.log(
      "frame",
      "epoch=" + CIKTrace.seconds(Date().timeIntervalSince1970 * 1000)
        + " t=" + CIKTrace.seconds(CACurrentMediaTime())
        + " refresh=" + CIKTrace.seconds(refresh)
        + " inset=" + CIKTrace.points(readPhysicalViewInsetBottom())
        + " bar=" + CIKTrace.points(hostedAccessoryBar?.frame.maxY)
        + " barShown=" + CIKTrace.points(hostedAccessoryBar?.layer.presentation()?.frame.maxY)
        + " guideTop=" + CIKTrace.points(guideTopInView())
    )
  }

  /// Writes the bottom inset of the engine, in physical pixels.
  private func publishInset(_ inset: CGFloat) {
    guard inset != lastReportedInset else { return }
    lastReportedInset = inset
    // Stop the engine's own inset animation, if one is in flight, only now that there is a value to
    // put in its place: while the plugin follows the finger the engine must not animate its own
    // inset on top of the live values. Invalidating it earlier would strand a half-finished show
    // animation if the plugin then had nothing to write.
    invalidateEngineAnimationIfNeeded()
    updateViewportMetrics(inset)
    syncEngineTargetInset(inset)
    CIKTrace.log(
      "inset",
      "inset=\(CIKTrace.points(inset)) engine=\(CIKTrace.points(readPhysicalViewInsetBottom()))"
    )
  }

  /// Writes the bottom view inset of the engine, in physical pixels.
  ///
  /// The engine exposes the setter of the viewport metrics only to Objective-C, so it is called
  /// through the runtime. It writes the position the keyboard has right now, so the next frame is
  /// laid out against it instead of one vsync later.
  private func updateViewportMetrics(_ inset: CGFloat) {
    let selector = NSSelectorFromString("updateViewportMetricsWithInset:")
    guard
      let flutterViewController,
      let method = class_getInstanceMethod(FlutterViewController.self, selector)
    else {
      logMissingEngineAPI("updateViewportMetricsWithInset:")
      return
    }

    typealias UpdateViewportMetricsFunction = @convention(c) (AnyObject, Selector, CGFloat) -> Void
    let updateViewportMetrics = unsafeBitCast(
      method_getImplementation(method),
      to: UpdateViewportMetricsFunction.self
    )
    updateViewportMetrics(flutterViewController, selector, inset)
  }

  /// Reads the inset the engine currently has, for the DEBUG trace only.
  ///
  /// The engine declares this on its keyboard inset manager delegate rather than in a public
  /// header, so it is called through the runtime like the setter.
  private func readPhysicalViewInsetBottom() -> CGFloat? {
    let selector = NSSelectorFromString("physicalViewInsetBottom")
    guard
      let flutterViewController,
      let method = class_getInstanceMethod(FlutterViewController.self, selector)
    else {
      return nil
    }
    typealias PhysicalViewInsetBottomFunction = @convention(c) (AnyObject, Selector) -> CGFloat
    let read = unsafeBitCast(
      method_getImplementation(method),
      to: PhysicalViewInsetBottomFunction.self
    )
    return read(flutterViewController, selector)
  }

  /// Keeps the target inset of the engine on the value the plugin just wrote.
  ///
  /// The engine ignores a keyboard notification whose computed inset equals its target, which is
  /// exactly the frame a cancelled drag is released at. Keeping the target on the live position
  /// means the release notification always differs from it, so the engine animates from the
  /// position the keyboard actually has instead of leaving the inset where the drag left it.
  private func syncEngineTargetInset(_ inset: CGFloat) {
    guard
      let flutterViewController,
      flutterViewController.responds(to: NSSelectorFromString("keyboardInsetManager")),
      let insetManager = flutterViewController.value(forKey: "keyboardInsetManager") as? NSObject
    else {
      logMissingEngineAPI("keyboardInsetManager")
      return
    }
    guard insetManager.responds(to: NSSelectorFromString("setTargetViewInsetBottom:")) else {
      logMissingEngineAPI("setTargetViewInsetBottom:")
      return
    }
    insetManager.setValue(inset, forKey: "targetViewInsetBottom")
  }

  /// Stops the engine's own inset animation once per tracking session, before the plugin's writes.
  private func invalidateEngineAnimationIfNeeded() {
    guard !invalidatedEngineAnimation else { return }
    invalidatedEngineAnimation = true
    invalidateEngineAnimation()
  }

  /// Stops the engine's own inset animation, if one is in flight.
  private func invalidateEngineAnimation() {
    guard
      let flutterViewController,
      flutterViewController.responds(to: NSSelectorFromString("keyboardInsetManager")),
      let insetManager = flutterViewController.value(forKey: "keyboardInsetManager") as? NSObject
    else {
      logMissingEngineAPI("keyboardInsetManager")
      return
    }
    guard insetManager.responds(to: NSSelectorFromString("invalidateKeyboardAnimationVSyncClient")) else {
      logMissingEngineAPI("invalidateKeyboardAnimationVSyncClient")
      return
    }
    insetManager.perform(NSSelectorFromString("invalidateKeyboardAnimationVSyncClient"))
  }

  /// Reports a missing private engine API once, so a future engine rename does not degrade the
  /// tracking silently.
  private func logMissingEngineAPI(_ name: String) {
    #if DEBUG
    NSLog(
      """
      cupertino_interactive_keyboard: the Flutter engine no longer answers \(name); keyboard \
      tracking falls back to the engine's own behaviour.
      """
    )
    #endif
  }

  /// The screen rect of a view, following the presentation tree while an animation is in
  /// flight.
  ///
  /// While the keyboard is dragged away UIKit moves it directly, so the model layer already holds
  /// the position of the frame that is about to be rendered. When the keyboard animates back into
  /// place after the release, the model layer holds the final position while the presentation
  /// layer holds the animated one, so the presentation layer is used in that case.
  private func liveScreenRect(of view: UIView, in screen: UIScreen) -> CGRect {
    let rect = view.convert(view.bounds, to: screen.coordinateSpace)

    // Find the closest animated ancestor. The keyboard is translated rather than scaled, so the
    // distance between its animated and its final frame is the offset that is still missing from
    // the model geometry.
    var ancestor = view.superview
    while let current = ancestor {
      if
        current.layer.animationKeys()?.isEmpty == false,
        let presentation = current.layer.presentation()
      {
        let animatedOrigin = presentation.frame.origin
        let finalOrigin = current.layer.frame.origin
        return rect.offsetBy(
          dx: animatedOrigin.x - finalOrigin.x,
          dy: animatedOrigin.y - finalOrigin.y
        )
      }
      ancestor = current.superview
    }

    return rect
  }
}

private extension UIResponder {
  static let keyboardInteractiveDismissalNotification: Notification.Name = {
    if #available(iOS 12.0, *) {
      return .init(
        // UIKeyboardPrivateInteractiveDismissalDidBeginNotification
        "VUlLZXlib2FyZFByaXZhdGVJbnRlcmFjdGl2ZURpc21pc3NhbERpZEJlZ2luTm90aWZpY2F0aW9u"
          .base64Decoded
      )
    } else {
      return .init(
        // UITextEffectsWindowDidRotateNotification
        "VUlUZXh0RWZmZWN0c1dpbmRvd0RpZFJvdGF0ZU5vdGlmaWNhdGlvbg=="
          .base64Decoded
      )
    }
  }()
}

private extension String {
  var base64Decoded: String {
    Data(base64Encoded: self)
      .flatMap {
        String(data: $0, encoding: .utf8)
      }
    ?? self
  }
}
