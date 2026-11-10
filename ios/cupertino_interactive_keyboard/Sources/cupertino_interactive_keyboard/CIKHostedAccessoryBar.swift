import UIKit

/// The arguments of `createHostedAccessory`: which Dart entrypoint renders the bar and how tall
/// its Flutter content is. The plugin ships no bar content and no UI configuration of its own, so
/// the app owns everything the bar draws.
struct NativeAccessoryConfig {
  /// The Dart entrypoint of the app's accessory library.
  let entrypoint: String
  /// The library URI that declares the entrypoint.
  let libraryURI: String
  /// The height of the bar's Flutter content, bottom safe area excluded.
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
/// The plugin pins the bar to the Flutter view's `keyboardLayoutGuide`, so UIKit moves it with the
/// keyboard frame for frame and keeps it at the bottom of the screen while the keyboard is closed.
/// The bar only sizes the Flutter content it hosts: a second Flutter engine's view fills its
/// bounds, so the app's widget is drawn by Flutter while its position comes from UIKit.
class CIKHostedAccessoryBar: UIView {
  /// Called with the bar's total height whenever it changes, safe area included.
  var onHeightChange: ((CGFloat) -> Void)?

  /// The bar's bottom edge in its superview's coordinates, ignoring the release correction.
  ///
  /// `center` and `bounds` are not affected by `transform`, so this is the position Auto Layout
  /// gives the bar; the release correction offsets it visually.
  var bottomBeforeTransform: CGFloat {
    center.y + bounds.height / 2
  }

  /// The current height of the bar, safe area included.
  var barHeight: CGFloat {
    KeyboardGeometry.hostedAccessoryHeight(
      contentHeight: contentHeight,
      safeAreaBottom: safeAreaInsets.bottom
    )
  }

  private var contentHeight: CGFloat = 56
  private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 0)

  init(config: NativeAccessoryConfig) {
    // The second engine reports its own size only after its first frame, so the bar is sized from
    // the fixed content height it was configured with instead.
    contentHeight = config.height
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    heightConstraint.constant = contentHeight
    heightConstraint.isActive = true
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  /// Resizes the bar when the Flutter widget changes its content height.
  func apply(height: CGFloat) {
    contentHeight = height
    updateHeightIfNeeded()
  }

  /// Puts the accessory Flutter view into the bar and stretches it over the whole bar.
  func host(_ contentView: UIView) {
    contentView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(contentView)
    NSLayoutConstraint.activate([
      contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
      contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
      contentView.topAnchor.constraint(equalTo: topAnchor),
      contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    updateHeightIfNeeded()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    updateHeightIfNeeded()
    traceLayoutIfChanged()
  }

  private func updateHeightIfNeeded() {
    let height = barHeight
    guard abs(height - heightConstraint.constant) > 0.5 else { return }

    heightConstraint.constant = height
    onHeightChange?(height)
  }

  /// Logs the bar's position against the guide it is pinned to, change-only.
  private func traceLayoutIfChanged() {
    guard CIKTrace.isEnabled else { return }
    var guideTop: CGFloat?
    if #available(iOS 15.0, *) {
      guideTop = superview?.keyboardLayoutGuide.layoutFrame.minY
    }
    let bottom = frame.maxY
    if let lastBottom = tracedBottom, let lastGuide = tracedGuideTop,
      abs(lastBottom - bottom) < 0.5, abs(lastGuide - (guideTop ?? 0)) < 0.5
    {
      return
    }
    tracedBottom = bottom
    tracedGuideTop = guideTop
    CIKTrace.log(
      "bar",
      "bottom=\(CIKTrace.points(bottom)) auto=\(CIKTrace.points(bottomBeforeTransform)) guideTop=\(CIKTrace.points(guideTop)) correction=\(CIKTrace.points(transform.ty)) height=\(CIKTrace.points(bounds.height))"
    )
  }

  private var tracedBottom: CGFloat?
  private var tracedGuideTop: CGFloat?
}
