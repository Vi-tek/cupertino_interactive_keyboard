import Foundation
import QuartzCore
import UIKit

/// The DEBUG-only trace that confirms the keyboard release mechanism on device.
///
/// The file stays linked into release builds, but nothing is evaluated there: [isEnabled] is false
/// and every call site guards on it, with the message built lazily. It is off by default even in a
/// debug build (synchronous logging per keyboard frame costs the pacing it measures) and is enabled
/// for a run with `-CIKTrace YES`.
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
  /// Off unless the app was launched with `-CIKTrace YES`: launch arguments reach UserDefaults as
  /// strings, so the value is parsed with `bool(forKey:)`.
  static let isEnabled: Bool = {
    guard isDebugBuild else { return false }
    let defaults = UserDefaults.standard
    guard defaults.object(forKey: "CIKTrace") != nil else { return false }
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
