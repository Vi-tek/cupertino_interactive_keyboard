import Foundation
import QuartzCore
import UIKit

/// The DEBUG-only trace that confirms the keyboard release mechanism on device.
///
/// The file stays linked into release builds, but nothing is evaluated there: [isEnabled] is false
/// and every call site guards on it, with the message built lazily. In a debug build the trace is on
/// unless the app is launched with `-CIKTrace NO`.
enum CIKTrace {
  /// Whether this binary is a debug build.
  ///
  /// Plain SwiftPM builds do not define the `DEBUG` compilation condition, so `assert` decides
  /// instead: it is compiled out of release builds.
  private static let isDebugBuild: Bool = {
    var isDebug = false
    assert({ isDebug = true; return true }())
    return isDebug
  }()

  /// Whether the trace should log.
  ///
  /// Launch arguments reach UserDefaults as strings, so the value is parsed with
  /// `bool(forKey:)`; without an override the build type decides.
  static let isEnabled: Bool = {
    let defaults = UserDefaults.standard
    guard defaults.object(forKey: "CIKTrace") != nil else { return isDebugBuild }
    return defaults.bool(forKey: "CIKTrace")
  }()

  static func log(_ tag: String, _ message: @autoclosure () -> String) {
    guard isEnabled else { return }
    NSLog("[CIKTrace] t=%.4f %@ %@", CACurrentMediaTime(), tag, message())
  }

  static func points(_ value: CGFloat?) -> String {
    guard let value else { return "nil" }
    return String(format: "%.2f", value)
  }

  static func seconds(_ value: Double) -> String {
    String(format: "%.3f", value)
  }

  static func rect(_ value: CGRect?) -> String {
    guard let value else { return "nil" }
    return String(
      format: "(%.1f,%.1f %.1fx%.1f)",
      value.origin.x,
      value.origin.y,
      value.width,
      value.height
    )
  }
}
