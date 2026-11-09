import Flutter
import UIKit

class KeyboardManager {
  static let shared = KeyboardManager()
  private static let handledUserInfoKey = "KeyboardManagerHandledUserInfoKey"
  static let syntheticUserInfoKey = "KeyboardManagerSyntheticUserInfoKey"

  var activeScrollViews = Set<CIKScrollView>()
  var activeInputAccessoryViews = Set<CIKInputAccessoryView>()

  weak var flutterViewController: FlutterViewController?

  private var interactiveTrackingDisplayLink: CADisplayLink?
  private var lastReportedInset: CGFloat?
  private var trackingTicks = 0
  private var consecutiveStaticTicks = 0

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

  /// Called from the swizzled keyboard notification handlers before the engine processes them.
  /// A real keyboard notification means the interactive dismissal has ended (or the keyboard is
  /// changing for another reason), so the engine takes over the inset animation from here.
  func willProcessKeyboardNotification(_ notification: Notification?) {
    guard
      let notification,
      (notification.userInfo?[KeyboardManager.syntheticUserInfoKey] as? Bool) != true
    else {
      return
    }
    if notification.name == UIResponder.keyboardWillHideNotification ||
       notification.name == UIResponder.keyboardDidHideNotification ||
       notification.name == UIResponder.keyboardDidShowNotification {
      stopInteractiveTracking()
      return
    }
    guard
      let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
      frame != .zero
    else {
      return
    }
    stopInteractiveTracking()
  }

  func stopInteractiveTracking() {
    interactiveTrackingDisplayLink?.invalidate()
    interactiveTrackingDisplayLink = nil
    lastReportedInset = nil
    trackingTicks = 0
    consecutiveStaticTicks = 0
  }

  @objc
  private func interactiveDismissalDidChange() {
    reportLiveKeyboardInset()
    startInteractiveTracking()
  }

  /// Starts live keyboard tracking if a keyboard accessory view is currently on screen.
  /// Called when the dismissal gesture begins, so tracking starts before the keyboard moves.
  func startTrackingIfKeyboardVisible() {
    guard activeInputAccessoryViews.contains(where: { $0.window != nil }) else { return }
    startInteractiveTracking()
    reportLiveKeyboardInset()
  }

  private func startInteractiveTracking() {
    guard interactiveTrackingDisplayLink == nil else { return }
    lastReportedInset = nil
    trackingTicks = 0
    consecutiveStaticTicks = 0

    // Invalidate the engine's active animation client so it does not fight live gesture tracking.
    if
      let flutterViewController,
      flutterViewController.responds(to: NSSelectorFromString("keyboardInsetManager")),
      let insetManager = flutterViewController.value(forKey: "keyboardInsetManager") as? NSObject,
      insetManager.responds(to: NSSelectorFromString("invalidateKeyboardAnimationVSyncClient"))
    {
      insetManager.perform(NSSelectorFromString("invalidateKeyboardAnimationVSyncClient"))
    }

    let displayLink = CADisplayLink(target: self, selector: #selector(trackInteractiveKeyboard))
    displayLink.add(to: .main, forMode: .common)
    interactiveTrackingDisplayLink = displayLink
  }

  @objc
  private func trackInteractiveKeyboard() {
    trackingTicks += 1
    let previousInset = lastReportedInset
    reportLiveKeyboardInset()

    let isGestureActive = activeScrollViews.contains {
      let state = $0.panGestureRecognizer.state
      return state == .began || state == .changed
    }

    if !isGestureActive {
      if lastReportedInset == previousInset {
        consecutiveStaticTicks += 1
      } else {
        consecutiveStaticTicks = 0
      }
    } else {
      consecutiveStaticTicks = 0
    }

    // Keep tracking alive during release (inertia or snap-back) until the keyboard settles at rest.
    let hasSettled = !isGestureActive && (consecutiveStaticTicks >= 5 || (lastReportedInset ?? 0) <= 0)
    if hasSettled || trackingTicks > 600 {
      stopInteractiveTracking()
    }
  }

  /// Reports the keyboard's live frame to the engine as the current bottom view inset.
  ///
  /// Uses the presentationLayer geometry of the active input accessory view in the keyboard window,
  /// mapped to the FlutterViewController view's coordinate space.
  private func reportLiveKeyboardInset() {
    guard
      let flutterViewController,
      let view = flutterViewController.view,
      let accessoryView = activeInputAccessoryViews.first(where: { $0.window != nil }),
      let accessoryWindow = accessoryView.window
    else {
      return
    }

    // Read the live presentation layer to follow UIKit's interactive animations without lag
    let presentationLayer = accessoryView.layer.presentation() ?? accessoryView.layer
    let rectInWindow = presentationLayer.convert(presentationLayer.bounds, to: accessoryWindow.layer)
    let rectInView = view.convert(rectInWindow, from: accessoryWindow)

    let insetPoints = max(0, view.bounds.height - rectInView.maxY)
    let screen = accessoryWindow.screen
    let scale = screen.scale
    let inset = insetPoints * scale
    guard inset != lastReportedInset else { return }
    lastReportedInset = inset

    if !updateViewportMetrics(inset, in: flutterViewController) {
      postSyntheticKeyboardFrame(
        CGRect(
          x: 0,
          y: rectInView.minY,
          width: view.bounds.width,
          height: max(0, view.bounds.height - rectInView.minY)
        ),
        screen: screen
      )
    }
  }

  /// Updates the engine's physical bottom view inset synchronously, so the next Flutter frame is
  /// laid out against the position the keyboard has right now instead of one vsync later.
  private func updateViewportMetrics(_ inset: CGFloat, in viewController: FlutterViewController) -> Bool {
    let updateSelector = NSSelectorFromString("updateViewportMetricsWithInset:")
    guard
      let method = class_getInstanceMethod(type(of: viewController), updateSelector),
      viewController.responds(to: NSSelectorFromString("keyboardInsetManager"))
    else {
      return false
    }

    typealias UpdateViewportMetricsFunction = @convention(c) (AnyObject, Selector, CGFloat) -> Void
    let updateViewportMetrics = unsafeBitCast(method_getImplementation(method), to: UpdateViewportMetricsFunction.self)
    updateViewportMetrics(viewController, updateSelector, inset)
    return true
  }

  private func postSyntheticKeyboardFrame(_ frame: CGRect, screen: UIScreen) {
    NotificationCenter.default.post(
      name: UIResponder.keyboardWillChangeFrameNotification,
      object: screen,
      userInfo: [
        UIResponder.keyboardFrameBeginUserInfoKey: NSValue(cgRect: frame),
        UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: frame),
        UIResponder.keyboardAnimationDurationUserInfoKey: 0.0,
        KeyboardManager.syntheticUserInfoKey: true,
      ]
    )
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
