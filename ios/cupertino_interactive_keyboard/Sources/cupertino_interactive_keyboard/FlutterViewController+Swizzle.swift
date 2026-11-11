import UIKit
import Flutter

@discardableResult
func swizzleFlutterViewController() -> Bool {
  swizzleFlutterViewControllerOnce
}

private let swizzleFlutterViewControllerOnce: Bool = ({
  let type = FlutterViewController.self
  return [
    exchangeSelectors(type, NSSelectorFromString("keyboardWillChangeFrame:"), #selector(FlutterViewController.cik_keyboardWillChangeFrame)),
    exchangeSelectors(type, NSSelectorFromString("keyboardWillBeHidden:"), #selector(FlutterViewController.cik_keyboardWillBeHidden)),
    exchangeSelectors(type, NSSelectorFromString("keyboardWillShowNotification:"), #selector(FlutterViewController.cik_keyboardWillShowNotification)),
  ].contains(true)
})()

extension FlutterViewController {
  @objc
  dynamic fileprivate func cik_keyboardWillChangeFrame(_ notification: Notification?) {
    handleKeyboardNotification(notification) {
      cik_keyboardWillChangeFrame(notification.map(KeyboardManager.shared.adjustKeyboardNotification(_:)))
    }
  }

  @objc
  dynamic fileprivate func cik_keyboardWillBeHidden(_ notification: Notification?) {
    handleKeyboardNotification(notification) {
      cik_keyboardWillBeHidden(notification.map(KeyboardManager.shared.adjustKeyboardNotification(_:)))
    }
  }

  @objc
  dynamic fileprivate func cik_keyboardWillShowNotification(_ notification: Notification?) {
    handleKeyboardNotification(notification) {
      cik_keyboardWillShowNotification(notification.map(KeyboardManager.shared.adjustKeyboardNotification(_:)))
    }
  }

  /// Runs the plugin's hand-off around the engine's own keyboard notification handling.
  ///
  /// The plugin stops driving the inset before the engine sees the notification (so the engine
  /// animates from the live position), and corrects the hosted bar after the engine has laid the
  /// release out. The keyboard's original notification is used for the bar: only the engine needs
  /// the accessory-adjusted frame.
  private func handleKeyboardNotification(
    _ notification: Notification?,
    engine: () -> Void
  ) {
    // The hosted surface engine keeps a fixed layout and is moved by a transform: it must never
    // see a keyboard inset, or the hosted content would re-lay out on every keyboard frame. The
    // main engine's controller drives the surface position instead.
    if KeyboardManager.shared.isHostedSurface(self) {
      return
    }
    let wasTracking = KeyboardManager.shared.isTrackingKeyboard
    KeyboardManager.shared.willProcessKeyboardNotification(notification)
    if let notification, KeyboardManager.shared.ownsInstantCollapse(notification) {
      // The engine would write the end inset in one frame; the plugin animates it down instead.
      KeyboardManager.shared.ownedCollapseTransition(notification)
      return
    }
    engine()
    guard let notification else { return }
    KeyboardManager.shared.keyboardNotificationHandled(notification, wasTracking: wasTracking)
  }
}
