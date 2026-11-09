import UIKit

/// The configuration of the hosted accessory bar as it arrives over the method channel.
///
/// Every field is optional: `createHostedAccessory` sends the full map and
/// `updateHostedAccessory` sends any subset, so a missing field keeps the current value (and, on
/// creation, the platform default). The bar itself only needs `height` and the entrypoint fields;
/// everything else is forwarded verbatim to the accessory Flutter engine, which renders the bar.
struct NativeAccessoryConfig {
  var placeholder: String?
  var text: String?
  var icon: String?
  var backgroundColor: UIColor?
  var textColor: UIColor?
  var placeholderColor: UIColor?
  var iconColor: UIColor?
  /// The height of the bar's Flutter content, bottom safe area excluded.
  var height: CGFloat?
  /// The Dart entrypoint of the accessory app, when the app ships its own.
  var accessoryEntrypoint: String?
  /// The Dart library URI of the accessory entrypoint, when the app ships its own.
  var accessoryLibraryURI: String?

  init?(arguments: Any?) {
    guard let arguments = arguments as? [String: Any] else { return nil }

    placeholder = arguments["placeholder"] as? String
    text = arguments["text"] as? String
    icon = arguments["icon"] as? String
    backgroundColor = NativeAccessoryConfig.color(arguments["backgroundColor"])
    textColor = NativeAccessoryConfig.color(arguments["textColor"])
    placeholderColor = NativeAccessoryConfig.color(arguments["placeholderColor"])
    iconColor = NativeAccessoryConfig.color(arguments["iconColor"])
    height = (arguments["height"] as? NSNumber).map { CGFloat($0.doubleValue) }
    accessoryEntrypoint = arguments["accessoryEntrypoint"] as? String
    accessoryLibraryURI = arguments["accessoryLibraryURI"] as? String
  }

  /// Parses an ARGB integer (`0xAARRGGBB`) into a color.
  private static func color(_ value: Any?) -> UIColor? {
    guard let number = value as? NSNumber else { return nil }

    let argb = UInt32(truncatingIfNeeded: number.int64Value)
    return UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }
}

/// The host container of the plugin's input accessory bar.
///
/// The plugin pins the bar to the Flutter view's `keyboardLayoutGuide`, so UIKit moves it with the
/// keyboard frame for frame and keeps it at the bottom of the screen while the keyboard is closed.
/// The bar only sizes the Flutter content it hosts: a second Flutter engine's view fills its
/// bounds, so the composer the user sees is drawn by Flutter while its position comes from UIKit.
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
    contentHeight = config.height ?? 56
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    heightConstraint.constant = contentHeight
    heightConstraint.isActive = true
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  /// Resizes the bar when the Flutter widget changes its content height.
  func apply(height: CGFloat?) {
    guard let height else { return }

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
