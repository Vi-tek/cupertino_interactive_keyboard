import Flutter
import UIKit

class KeyboardManager {
  static let shared = KeyboardManager()
  private static let handledUserInfoKey = "KeyboardManagerHandledUserInfoKey"

  var activeScrollViews = Set<CIKScrollView>()
  var activeInputAccessoryViews = Set<CIKInputAccessoryView>()

  weak var flutterViewController: FlutterViewController?

  /// The channel the plugin pushes the live translation of the accessory on. Only the plugin owns
  /// the channel of the engine, so it hands it over.
  weak var channel: FlutterMethodChannel?

  private var interactiveTrackingDisplayLink: CADisplayLink?
  private var lastReportedTranslation: CGFloat?
  private var lastBandBottom: CGFloat?
  private var staticTicks = 0
  private var trackingTicks = 0

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

  // MARK: - Interactive dismissal

  /// Whether the plugin is in charge of the position of the accessory.
  private var isDrivingTranslation: Bool {
    interactiveTrackingDisplayLink != nil
  }

  /// Whether the user is currently dragging the keyboard away.
  private var isDraggingKeyboard: Bool {
    activeScrollViews.contains {
      let state = $0.panGestureRecognizer.state
      return state == .began || state == .changed
    }
  }

  /// Called from the swizzled keyboard notification handlers before the engine processes them.
  ///
  /// The engine animates the viewport inset towards the notified frame over the animation duration
  /// of the notification, which makes the Flutter accessory trail behind the keyboard. While the
  /// plugin drives the position of the accessory itself, the notifications are handed over
  /// unchanged, so the content of the app keeps following the keyboard the way it always did.
  func willProcessKeyboardNotification(_ notification: Notification?) {
    guard let notification else { return }

    if notification.name == UIResponder.keyboardWillHideNotification {
      // The keyboard is gone for good.
      stopInteractiveTracking()
    }
  }

  /// Starts live keyboard tracking if a keyboard accessory view is currently on screen.
  ///
  /// Called when the dismissal gesture begins, so tracking starts before the keyboard moves.
  func startTrackingIfKeyboardVisible() {
    guard activeInputAccessoryViews.contains(where: { $0.window != nil }) else { return }
    startInteractiveTracking()
  }

  private func startInteractiveTracking() {
    guard interactiveTrackingDisplayLink == nil else { return }
    lastReportedTranslation = nil
    lastBandBottom = nil
    staticTicks = 0
    trackingTicks = 0

    let displayLink = CADisplayLink(target: self, selector: #selector(trackInteractiveKeyboard))
    displayLink.add(to: .main, forMode: .common)
    interactiveTrackingDisplayLink = displayLink
  }

  func stopInteractiveTracking() {
    interactiveTrackingDisplayLink?.invalidate()
    interactiveTrackingDisplayLink = nil
    lastReportedTranslation = nil
    lastBandBottom = nil
    staticTicks = 0
    trackingTicks = 0
    reportTranslation(0)
  }

  @objc
  private func interactiveDismissalDidChange() {
    startTrackingIfKeyboardVisible()
  }

  @objc
  private func trackInteractiveKeyboard() {
    trackingTicks += 1
    let bandBottom = reportLiveTranslation()

    let hasStoppedMoving = bandBottom != nil && bandBottom == lastBandBottom
    lastBandBottom = bandBottom
    staticTicks = hasStoppedMoving ? staticTicks + 1 : 0

    // The tracking ends once the keyboard came to rest. While the keyboard keeps moving, either
    // because it is dragged or because it animates back into place, the plugin stays in charge of
    // the position of the accessory.
    let hasSettled = KeyboardGeometry.shouldStopTracking(
      isDragging: isDraggingKeyboard,
      hasStoppedMoving: hasStoppedMoving,
      staticTicks: staticTicks
    )
    if hasSettled || trackingTicks > 600 {
      stopInteractiveTracking()
    }
  }

  /// Reports how far the accessory has to be moved to stay glued to the band.
  ///
  /// The accessory is laid out at the bottom of the content area, which is the bottom of the view
  /// minus the viewport inset the engine reports. The band is at the bottom of the view minus its
  /// own offset. The difference between both is the distance the accessory has to be moved.
  ///
  /// The band is read from the model layer on purpose: while the keyboard follows the finger the
  /// model layer already holds the position of the frame that is about to be rendered, while the
  /// presentation layer would still hold the position of the previous frame. When the keyboard
  /// animates back into place after the release, the model layer holds the final position while the
  /// presentation layer holds the animated one, so the presentation layer is used in that case.
  @discardableResult
  private func reportLiveTranslation() -> CGFloat? {
    guard
      let accessoryView = activeInputAccessoryViews.first(where: { $0.window != nil }),
      let window = accessoryView.window
    else {
      return nil
    }
    let screen = window.screen

    let bandRect = liveScreenRect(of: accessoryView, in: screen)
    let bandBottom = bandRect.maxY
    let bandOffset = KeyboardGeometry.bandOffset(
      bandBottom: bandBottom,
      screenBottom: screen.bounds.maxY
    )
    let translation = KeyboardGeometry.accessoryTranslation(
      viewportInset: currentViewportInset(),
      bandOffset: bandOffset
    )

    guard translation != lastReportedTranslation else { return bandBottom }
    lastReportedTranslation = translation

    reportTranslation(translation)
    return bandBottom
  }

  /// The bottom inset the engine currently reports, in points.
  private func currentViewportInset() -> CGFloat {
    guard
      let flutterViewController,
      flutterViewController.responds(to: NSSelectorFromString("keyboardInsetManager")),
      let insetManager = flutterViewController.value(forKey: "keyboardInsetManager") as? NSObject,
      insetManager.responds(to: NSSelectorFromString("physicalViewInsetBottom")),
      let inset = insetManager.value(forKey: "physicalViewInsetBottom") as? NSNumber
    else {
      return 0
    }
    let scale = flutterViewController.view.window?.screen.scale ?? 1
    return inset.doubleValue / scale
  }

  /// Pushes the translation of the accessory to the Flutter side.
  ///
  /// The translation is pushed instead of writing the viewport inset, because a change of the
  /// viewport inset rebuilds and relayouts the whole widget tree on every frame, which drops frames
  /// and makes the accessory trail behind the keyboard.
  private func reportTranslation(_ translation: CGFloat) {
    guard let channel else { return }
    channel.invokeMethod("setKeyboardTranslation", arguments: ["translation": translation])
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
