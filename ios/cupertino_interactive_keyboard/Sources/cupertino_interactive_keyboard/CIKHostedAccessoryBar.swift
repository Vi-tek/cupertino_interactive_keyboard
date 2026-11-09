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
  }

  private func updateHeightIfNeeded() {
    let height = barHeight
    guard abs(height - heightConstraint.constant) > 0.5 else { return }

    heightConstraint.constant = height
    onHeightChange?(height)
  }
}
