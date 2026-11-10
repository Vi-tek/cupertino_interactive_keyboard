import Flutter
import QuartzCore
import UIKit

class KeyboardManager {
  static let shared = KeyboardManager()
  private static let handledUserInfoKey = "KeyboardManagerHandledUserInfoKey"

  var activeScrollViews = Set<CIKScrollView>()
  var activeInputAccessoryViews = Set<CIKInputAccessoryView>()

  weak var flutterViewController: FlutterViewController?

  /// The hosted accessory bar, when the Dart side uses one. It becomes the live band: its bottom
  /// edge is the keyboard's top edge while the keyboard is open and the view's bottom edge while it
  /// is closed, so the same inset formula keeps the content glued to it either way.
  weak var hostedAccessoryBar: CIKHostedAccessoryBar?

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
    syncInset()
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

  private func startInteractiveTracking() {
    guard interactiveTrackingDisplayLink == nil else { return }
    lastReportedInset = nil
    lastBandBottom = nil
    staticTicks = 0
    trackingTicks = 0
    missingBandTicks = 0
    isInsetSyncScheduled = false
    invalidatedEngineAnimation = false

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
    lastReportedInset = nil
    // `lastBandBottom` is deliberately kept: the release hand-off starts its correction from the
    // band's last live position, which is only known while the session is running.
    staticTicks = 0
    trackingTicks = 0
    missingBandTicks = 0
    isInsetSyncScheduled = false
    invalidatedEngineAnimation = false
  }

  /// The animation key of the bar's release correction, so it can be told apart from UIKit's own.
  private static let releaseCorrectionKey = "cikReleaseCorrection"

  /// Records the band's position when the drag ends.
  ///
  /// The last display-link tick can be a frame old, and a release that ends the session before the
  /// next tick would start the correction from the wrong position.
  func keyboardDragDidEnd() {
    guard interactiveTrackingDisplayLink != nil else { return }
    lastBandBottom = syncInset() ?? lastBandBottom
  }

  /// Reconciles the bar with the keyboard after a notification.
  ///
  /// The keyboard layout guide follows the drag, but its only documented contract is a docked
  /// keyboard's show/hide animation: on release the guide is moved to the end position in one step,
  /// so a bar pinned to it snaps while the keyboard keeps animating. This animates the difference
  /// between where the bar has to be and where Auto Layout put it, with the keyboard notification's
  /// own duration and curve.
  ///
  /// The correction is also reconciled on every later notification while it is non-zero: when the
  /// guide catches up it animates back to zero, and when it moves somewhere else the offset is
  /// re-targeted instead of being added on top of the guide's position. A correction that stays
  /// non-zero after both is logged - that is the case the plugin-owned geometry has to take over.
  func keyboardNotificationHandled(_ notification: Notification, wasTracking: Bool) {
    guard !isIgnoredByEngine(notification) else { return }
    // A normal (non-interactive) transition only needs the bar when a correction is still applied.
    guard wasTracking || abs(hostedAccessoryBar?.transform.ty ?? 0) > 0.5 else { return }
    // UIKit can post the release notification while the dismissal recognizer is still in its
    // begin/changed phase. One runloop turn later the gesture is over and the correction is not
    // lost; if it is not over, the drag is still in charge.
    if wasTracking, isDraggingKeyboard {
      CIKTrace.log(
        "release",
        "deferred: still dragging notification=" + notification.name.rawValue
      )
      DispatchQueue.main.async { [weak self] in
        self?.applyBarCorrection(notification, wasTracking: true)
      }
      return
    }
    applyBarCorrection(notification, wasTracking: wasTracking)
  }

  private func applyBarCorrection(_ notification: Notification, wasTracking: Bool) {
    guard
      let bar = hostedAccessoryBar,
      bar.window != nil,
      let flutterViewController,
      let flutterView = flutterViewController.view,
      let window = flutterView.window
    else {
      return
    }
    if wasTracking, isDraggingKeyboard {
      CIKTrace.log("release", "skip: still dragging after the deferral")
      return
    }
    let info = notification.userInfo
    guard let endFrame = (info?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
    else {
      return
    }
    let duration =
      (info?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
    let curve = (info?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 7
    let screen = window.screen

    // The visual position has to be read before Auto Layout is forced to the release's end position.
    let visualBottomBeforeLayout = bar.frame.maxY
    let heldCorrection = bar.transform.ty
    flutterView.layoutIfNeeded()

    // UIKit already animating the bar means this transition went through the guide; leave it alone.
    let otherAnimations = (bar.layer.animationKeys() ?? []).filter {
      $0 != Self.releaseCorrectionKey
    }
    if !otherAnimations.isEmpty {
      CIKTrace.log(
        "release",
        "skip: bar layer animating keys=" + otherAnimations.joined(separator: ",")
          + " notification=" + notification.name.rawValue
      )
      return
    }

    let viewRect = liveScreenRect(of: flutterView, in: screen)
    // A hidden, empty or floating keyboard leaves no band, so the bar belongs at the view's bottom.
    let hidden =
      notification.name == UIResponder.keyboardWillHideNotification
      || endFrame.isEmpty
      || !KeyboardGeometry.isDockedBand(bandWidth: endFrame.width, viewWidth: viewRect.width)
    let targetBottom = max(
      0,
      KeyboardGeometry.releaseBandBottom(
        keyboardTop: hidden ? nil : endFrame.minY,
        viewBottom: viewRect.maxY
      ) - viewRect.minY
    )
    let autoBottom = bar.bottomBeforeTransform
    let wanted = targetBottom - autoBottom
    // A release starts where the bar was last drawn; a reconciliation starts from the held offset.
    let start: CGFloat
    if wasTracking {
      start = (lastBandBottom.map { $0 - viewRect.minY } ?? visualBottomBeforeLayout) - autoBottom
    } else {
      start = heldCorrection
    }
    CIKTrace.log(
      "release",
      "notification=" + notification.name.rawValue
        + " duration=" + CIKTrace.seconds(duration)
        + " curve=" + String(curve)
        + " target=" + CIKTrace.points(targetBottom)
        + " auto=" + CIKTrace.points(autoBottom)
        + " start=" + CIKTrace.points(start)
        + " wanted=" + CIKTrace.points(wanted)
        + " held=" + CIKTrace.points(heldCorrection)
    )

    if abs(wanted - start) <= 0.5 {
      // Nothing to travel; drop a stale offset if the guide caught up.
      if abs(heldCorrection - wanted) > 0.5 {
        setBarCorrection(bar, wanted)
      }
      return
    }

    // An explicit `fromValue` is used instead of `UIView.animate`: the bar's layout already jumped
    // to the end position, so an implicit animation would start from the wrong value.
    let animation = CABasicAnimation(keyPath: "transform.translation.y")
    animation.fromValue = start
    animation.toValue = wanted
    animation.duration = duration
    animation.timingFunction = timingFunction(forCurve: curve)
    bar.layer.add(animation, forKey: Self.releaseCorrectionKey)
    setBarCorrection(bar, wanted)
  }

  /// Sets the bar's correction without a competing implicit animation.
  private func setBarCorrection(_ bar: CIKHostedAccessoryBar, _ correction: CGFloat) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    bar.transform = CGAffineTransform(translationX: 0, y: correction)
    CATransaction.commit()
  }

  /// The keyboard notification's curve, as a timing function the correction can follow.
  ///
  /// Curve 7 is UIKit's private keyboard curve; its spring is not exposed, so the classic keyboard
  /// control points are used.
  private func timingFunction(forCurve curve: UInt) -> CAMediaTimingFunction {
    switch curve {
    case 0: return CAMediaTimingFunction(name: .easeInEaseOut)
    case 1: return CAMediaTimingFunction(name: .easeIn)
    case 2: return CAMediaTimingFunction(name: .easeOut)
    case 3: return CAMediaTimingFunction(name: .linear)
    default: return CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
    }
  }

  @objc
  private func interactiveDismissalDidChange() {
    startTrackingIfKeyboardVisible()
  }

  @objc
  private func trackInteractiveKeyboard() {
    trackingTicks += 1
    let bandBottom = syncInset()

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

  /// Writes the viewport inset that keeps the content glued to the live keyboard band.
  ///
  /// The band is read from the model layer on purpose: while the keyboard follows the finger the
  /// model layer already holds the position of the frame that is about to be rendered, while the
  /// presentation layer would still hold the position of the previous frame. When the keyboard
  /// animates back into place after the release, the model layer holds the final position while the
  /// presentation layer holds the animated one, so the presentation layer is used in that case.
  ///
  /// - Returns: The bottom edge of the band in screen coordinates, if it is on screen.
  @discardableResult
  private func syncInset() -> CGFloat? {
    guard
      let flutterViewController,
      let flutterView = flutterViewController.view,
      flutterView.window != nil
    else {
      return nil
    }

    let hostedBar = hostedAccessoryBar.flatMap { $0.window != nil ? $0 : nil }
    guard
      let accessoryView = hostedBar ?? activeInputAccessoryViews.first(where: { $0.window != nil }),
      let window = accessoryView.window
    else {
      return nil
    }
    let screen = window.screen

    let bandRect = liveScreenRect(of: accessoryView, in: screen)
    let viewRect = liveScreenRect(of: flutterView, in: screen)

    // A floating keyboard has no inset in the engine, so it must not be driven here either. The
    // hosted bar spans the Flutter view by construction, so the guard only applies to the Flutter
    // accessory view, which UIKit can put in a floating keyboard.
    if hostedBar == nil,
      !KeyboardGeometry.isDockedBand(bandWidth: bandRect.width, viewWidth: viewRect.width)
    {
      return nil
    }

    let bandBottom = bandRect.maxY
    let inset = KeyboardGeometry.inset(
      bandBottom: bandBottom,
      viewBottom: viewRect.maxY,
      scale: screen.scale
    )

    guard inset != lastReportedInset else { return bandBottom }
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
      "band=\(CIKTrace.points(bandBottom)) inset=\(CIKTrace.points(inset)) engine=\(CIKTrace.points(readPhysicalViewInsetBottom()))"
    )
    return bandBottom
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

  /// Stops the engine's own inset animation once the plugin is about to write its own value.
  private func invalidateEngineAnimationIfNeeded() {
    guard !invalidatedEngineAnimation else { return }
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
    invalidatedEngineAnimation = true
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
