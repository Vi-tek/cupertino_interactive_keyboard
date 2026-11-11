import Flutter
import UIKit

/// Adds a hit-test bridge to FlutterView so a behind surface can receive the touches the app lets
/// through its hole.
///
/// The Flutter view is above the surface; when the point is inside the hole the Flutter view must
/// not claim the touch, so UIKit falls through to the surface below. The check lives in the
/// manager, because it needs the live keyboard inset and the app's interactive flag.
///
/// `FlutterView` is not exported in the Flutter module headers, so it is looked up by name at
/// runtime; the class is the one every `FlutterViewController` creates.
@discardableResult
func swizzleFlutterViewHitTest() -> Bool {
  swizzleFlutterViewHitTestOnce
}

private let swizzleFlutterViewHitTestOnce: Bool = ({
  guard let flutterViewClass = NSClassFromString("FlutterView") else {
    CIKTrace.log("hitTest", "FlutterView not found; behind passthrough disabled")
    return false
  }
  let selector = #selector(UIView.hitTest(_:with:))
  guard let method = class_getInstanceMethod(flutterViewClass, selector) else {
    CIKTrace.log("hitTest", "FlutterView has no hitTest:; behind passthrough disabled")
    return false
  }
  typealias HitTestFunction = @convention(c) (AnyObject, Selector, CGPoint, UIEvent?) -> UIView?
  let original = unsafeBitCast(
    method_getImplementation(method),
    to: HitTestFunction.self
  )
  let block: @convention(block) (AnyObject, CGPoint, UIEvent?) -> UIView? = {
    object, point, event in
    if
      let view = object as? UIView,
      KeyboardManager.shared.shouldPassThroughFlutterTouch(view, point: point)
    {
      return nil
    }
    return original(object, selector, point, event)
  }
  let replaced = class_replaceMethod(
    flutterViewClass,
    selector,
    imp_implementationWithBlock(block),
    method_getTypeEncoding(method)
  )
  CIKTrace.log(
    "hitTest",
    "FlutterView hitTest installed=" + String(replaced != nil)
  )
  return replaced != nil
})()
