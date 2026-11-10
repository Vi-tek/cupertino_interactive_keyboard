import UIKit

/// The arguments of `createHostedAccessory`: which Dart entrypoint renders the bar and how tall
/// its Flutter content is. The plugin ships no bar content and no UI configuration of its own, so
/// the app owns everything the bar draws.
struct NativeAccessoryConfig {
  /// The Dart entrypoint of the app's accessory library.
  let entrypoint: String
  /// The library URI that declares the entrypoint.
  let libraryURI: String
  /// The height of the bar's Flutter content, bottom safe area excluded. Initial only: the accessory
  /// reports its own content height once it is laid out.
  let height: CGFloat
  /// Whether the bar starts hidden. A hidden bar keeps its engine alive but is neither drawn nor
  /// hit-tested, so it can be shown again on the next frame.
  let hidden: Bool

  init?(arguments: Any?) {
    guard
      let arguments = arguments as? [String: Any],
      let entrypoint = arguments["entrypoint"] as? String,
      let libraryURI = arguments["libraryURI"] as? String,
      let height = arguments["height"] as? NSNumber
    else {
      return nil
    }

    self.entrypoint = entrypoint
    self.libraryURI = libraryURI
    self.height = CGFloat(height.doubleValue)
    self.hidden = arguments["hidden"] as? Bool ?? false
  }
}

/// The host container of the plugin's input accessory bar.
///
/// The plugin positions the bar itself: a bottom constraint holds the bar at the keyboard's top edge
/// while the keyboard is on screen, and at the Flutter view's bottom once it is gone. The bar is not
/// tied to `keyboardLayoutGuide`, which is only live while the keyboard is dragged and snaps to its
/// end position on release.
///
/// The hosted Flutter view is pinned to the bar's top with the *content* height alone, so the
/// home-indicator padding the bar carries at rest never stretches the app's composer.
class CIKHostedAccessoryBar: UIView {
  /// Called with the bar's total height whenever it changes, safe area included.
  var onHeightChange: ((CGFloat) -> Void)?

  /// The height the bar's Flutter content asked for, safe area excluded.
  private(set) var contentHeight: CGFloat = 56

  /// Whether the home-indicator inset is part of the bar's height.
  ///
  /// Only at rest: while the keyboard is on screen the bar sits on it and no padding is needed.
  var includesSafeArea = false {
    didSet {
      guard includesSafeArea != oldValue else { return }
      updateLayoutIfNeeded()
    }
  }

  /// The bar's total height, safe area included.
  var barHeight: CGFloat {
    KeyboardGeometry.hostedAccessoryHeight(
      contentHeight: contentHeight,
      safeAreaBottom: includesSafeArea ? (superview?.safeAreaInsets.bottom ?? 0) : 0
    )
  }

  private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 0)
  private var bottomConstraint: NSLayoutConstraint?
  private var hostedHeightConstraint: NSLayoutConstraint?
  private var tracedBottom: CGFloat?

  init(config: NativeAccessoryConfig) {
    contentHeight = config.height
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    heightConstraint.isActive = true
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  /// Pins the bar to the bottom of [parent], [bottomInset] points above its bottom edge.
  func attach(to parent: UIView, bottomInset: CGFloat) {
    let bottom = bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -bottomInset)
    NSLayoutConstraint.activate([
      leadingAnchor.constraint(equalTo: parent.leadingAnchor),
      trailingAnchor.constraint(equalTo: parent.trailingAnchor),
      bottom,
    ])
    bottomConstraint = bottom
    updateLayoutIfNeeded()
  }

  /// Moves the bar's bottom edge [inset] points above the Flutter view's bottom.
  func setBottomInset(_ inset: CGFloat) {
    guard let bottomConstraint, abs(bottomConstraint.constant + inset) > 0.5 else { return }
    bottomConstraint.constant = -inset
  }

  /// Resizes the bar when the Flutter content changes its height.
  func apply(height: CGFloat) {
    contentHeight = height
    updateLayoutIfNeeded()
  }

  /// Puts the accessory Flutter view into the bar, pinned to its top at the content height.
  func host(_ contentView: UIView) {
    contentView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(contentView)
    let height = contentView.heightAnchor.constraint(equalToConstant: contentHeight)
    NSLayoutConstraint.activate([
      contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
      contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
      contentView.topAnchor.constraint(equalTo: topAnchor),
      height,
    ])
    hostedHeightConstraint = height
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    updateHeightIfNeeded()
    traceLayoutIfChanged()
  }

  private func updateLayoutIfNeeded() {
    updateHeightIfNeeded()
    setNeedsLayout()
  }

  private func updateHeightIfNeeded() {
    hostedHeightConstraint?.constant = contentHeight
    let height = barHeight
    guard abs(height - heightConstraint.constant) > 0.5 else { return }
    heightConstraint.constant = height
    onHeightChange?(height)
  }

  /// Logs the bar's geometry against the guide, change-only and only while the trace is enabled.
  private func traceLayoutIfChanged() {
    guard CIKTrace.isEnabled else { return }
    let bottom = frame.maxY
    guard tracedBottom == nil || abs((tracedBottom ?? bottom) - bottom) > 0.5 else { return }
    tracedBottom = bottom
    var guideTop: CGFloat?
    if #available(iOS 15.0, *) {
      guideTop = superview?.keyboardLayoutGuide.layoutFrame.minY
    }
    CIKTrace.log(
      "bar",
      "bottom=\(CIKTrace.points(bottom)) height=\(CIKTrace.points(bounds.height)) inset=\(CIKTrace.points(superview.map { $0.bounds.height - bottom })) guideTop=\(CIKTrace.points(guideTop)) padding=\(CIKTrace.points(includesSafeArea ? superview?.safeAreaInsets.bottom : 0))"
    )
  }
}
