import Foundation
import QuartzCore
import UIKit

/// The DEBUG-only trace that confirms the keyboard pacing on device.
///
/// Off by default. The app turns it on with `setKeyboardTraceEnabled(true)` from Dart (see the
/// plugin's public helper), which forwards every line to the Dart console, so a `flutter run`
/// session shows them. Release builds ignore the override.
enum CIKTrace {
  /// Forwards each line to the main isolate, which prints it to the Dart console.
  static var sink: ((String) -> Void)?

  private static var overrideEnabled: Bool?

  /// Whether this binary is a debug build.
  ///
  /// Plain SwiftPM builds do not define the `DEBUG` compilation condition, so `assert` decides
  /// instead: it is compiled out of release builds.
  private static let isDebugBuild: Bool = {
    var isDebug = false
    assert({ isDebug = true; return true }())
    return isDebug
  }()

  /// Whether the trace is on: only a debug build, and only when the app asked for it.
  static var isEnabled: Bool {
    overrideEnabled == true && isDebugBuild
  }

  /// Enables or disables the trace for this run.
  static func setEnabled(_ enabled: Bool) {
    overrideEnabled = isDebugBuild ? enabled : false
  }

  static func log(_ tag: String, _ message: @autoclosure () -> String) {
    guard isEnabled else { return }
    let line = "[CIKTrace] " + tag + " " + message()
    sink?(line)
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
