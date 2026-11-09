import Flutter
import UIKit

public class CupertinoInteractiveKeyboardPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    _ = KeyboardManager.shared
    swizzleFlutterViewController()
    swizzleFlutterTextInputView()
    
    let channel = FlutterMethodChannel(name: "cupertino_interactive_keyboard", binaryMessenger: registrar.messenger())
    let instance = CupertinoInteractiveKeyboardPlugin()
    instance.channel = channel
    registrar.publish(instance)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }
  
  static func instance(for registry: FlutterPluginRegistry) -> CupertinoInteractiveKeyboardPlugin? {
    registry.valuePublished(byPlugin: "CupertinoInteractiveKeyboardPlugin") as? CupertinoInteractiveKeyboardPlugin
  }
  
  private let scrollView = CIKScrollView()
  let inputView = CIKInputAccessoryView()
  private var channel: FlutterMethodChannel?
  private var hostedAccessoryBar: CIKHostedAccessoryBar?
  /// The latest config pushed by Dart, forwarded to the accessory engine.
  private var accessoryConfig: [String: Any] = [:]
  private var accessoryChannel: FlutterMethodChannel?
  private var accessoryEngine: FlutterEngine?
  private var accessoryViewController: FlutterViewController?
  private var engineGroup: FlutterEngineGroup?
    
  override init() {
    super.init()
  }
  
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      guard
        let args = call.arguments as? [String: Any],
        let firstTime = args["firstTime"] as? Bool
      else {
        return result(FlutterMethodNotImplemented)
      }
      
      DispatchQueue.main.async {
        if firstTime {
          self.scrollView.scrollabeRects = [:]
          self.inputView.inputAccessoryHeights = [:]
        }
        
        guard let flutterViewController = self.findFlutterViewController() else {
          return result(false)
        }
        KeyboardManager.shared.flutterViewController = flutterViewController
        
        if self.scrollView.superview != flutterViewController.view {
          self.scrollView.removeFromSuperview()
          self.scrollView.frame = flutterViewController.view.bounds
          flutterViewController.view.addSubview(self.scrollView)
        }
        
        result(true)
      }
      
    case "setScrollableRect":
      guard
        let args = call.arguments as? [String: Any],
        let id = args["id"] as? Int,
        let rectMap = args["rect"] as? [String: Double],
        let x = rectMap["x"],
        let y = rectMap["y"],
        let width = rectMap["width"],
        let height = rectMap["height"]
      else {
        return result(FlutterMethodNotImplemented)
      }
      
      DispatchQueue.main.async {
        self.scrollView.scrollabeRects[id] = CGRect(x: x, y: y, width: width, height: height)
        result(nil)
      }
      
    case "removeScrollableRect":
      guard
        let args = call.arguments as? [String: Any],
        let id = args["id"] as? Int
      else {
        return result(FlutterMethodNotImplemented)
      }
      
      DispatchQueue.main.async {
        self.scrollView.scrollabeRects[id] = nil
        result(nil)
      }
      
    case "setInputAccessoryHeight":
      guard
        let args = call.arguments as? [String: Any],
        let id = args["id"] as? Int,
        let height = args["height"] as? Double
      else {
        return result(FlutterMethodNotImplemented)
      }
      
      DispatchQueue.main.async {
        self.inputView.inputAccessoryHeights[id] = height
        result(nil)
      }
      
    case "removeInputAccessoryHeight":
      guard
        let args = call.arguments as? [String: Any],
        let id = args["id"] as? Int
      else {
        return result(FlutterMethodNotImplemented)
      }
      
      DispatchQueue.main.async {
        self.inputView.inputAccessoryHeights[id] = nil
        result(nil)
      }
      
    case "createHostedAccessory":
      guard
        let config = NativeAccessoryConfig(arguments: call.arguments),
        let arguments = call.arguments as? [String: Any]
      else {
        return result(FlutterMethodNotImplemented)
      }
      
      DispatchQueue.main.async {
        self.createHostedAccessory(config, arguments: arguments, result: result)
      }
      
    case "updateHostedAccessory":
      guard
        let config = NativeAccessoryConfig(arguments: call.arguments),
        let arguments = call.arguments as? [String: Any]
      else {
        return result(FlutterMethodNotImplemented)
      }
      
      DispatchQueue.main.async {
        self.accessoryConfig.merge(arguments) { _, new in new }
        // The widget may change its height; the bar has to keep the height the widget reserves.
        self.hostedAccessoryBar?.apply(height: config.height)
        self.pushAccessoryConfig()
        result(nil)
      }
      
    case "setHostedAccessoryText":
      guard
        let args = call.arguments as? [String: Any],
        let text = args["text"] as? String
      else {
        return result(FlutterMethodNotImplemented)
      }
      
      DispatchQueue.main.async {
        self.accessoryChannel?.invokeMethod("setText", arguments: ["text": text])
        result(nil)
      }
      
    case "removeHostedAccessory":
      DispatchQueue.main.async {
        self.tearDownHostedAccessory()
        result(nil)
      }
      
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  /// Creates the hosted accessory bar: a container glued to the keyboard layout guide, with a
  /// second Flutter engine rendering the composer inside it.
  ///
  /// `keyboardLayoutGuide` is iOS 15+, while the plugin's floor is iOS 13: on older systems the
  /// method returns nil and the Flutter widget keeps its own placeholder.
  private func createHostedAccessory(
    _ config: NativeAccessoryConfig,
    arguments: [String: Any],
    result: @escaping FlutterResult
  ) {
    guard #available(iOS 15.0, *) else {
      return result(nil)
    }
    guard
      let flutterViewController = KeyboardManager.shared.flutterViewController ?? findFlutterViewController()
    else {
      return result(nil)
    }
    // The Dart widget may create the bar before `initialize` runs; the tracking needs the view
    // controller either way.
    KeyboardManager.shared.flutterViewController = flutterViewController
    
    tearDownHostedAccessory()
    accessoryConfig = arguments
    
    let bar = CIKHostedAccessoryBar(config: config)
    // The hosted Flutter view is opaque black until its first frame; painting the bar with the
    // configured background keeps that flash invisible.
    bar.backgroundColor = config.backgroundColor ?? .systemBackground
    let flutterView = flutterViewController.view!
    flutterView.addSubview(bar)
    NSLayoutConstraint.activate([
      bar.leadingAnchor.constraint(equalTo: flutterView.leadingAnchor),
      bar.trailingAnchor.constraint(equalTo: flutterView.trailingAnchor),
      bar.bottomAnchor.constraint(equalTo: flutterView.keyboardLayoutGuide.topAnchor),
    ])
    // The bar carries its own bottom safe-area padding, so the guide must sit on the view's bottom
    // edge instead of above the home indicator while the keyboard is closed. `usesBottomSafeArea`
    // is iOS 17+; on iOS 15/16 the guide already rests on the bottom edge.
    if #available(iOS 17.0, *) {
      flutterView.keyboardLayoutGuide.usesBottomSafeArea = false
    }
    
    bar.onHeightChange = { [weak self] height in
      self?.channel?.invokeMethod("hostedAccessoryHeight", arguments: ["height": Double(height)])
    }
    
    let project = FlutterDartProject()
    let group = engineGroup
      ?? FlutterEngineGroup(name: "cupertino_interactive_keyboard.accessory", project: project)
    engineGroup = group
    let engine = group.makeEngine(
      withEntrypoint: config.accessoryEntrypoint ?? "cupertinoAccessoryMain",
      libraryURI: config.accessoryLibraryURI
        ?? "package:cupertino_interactive_keyboard/cupertino_accessory_entrypoint.dart"
    )
    
    let accessoryViewController = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    flutterViewController.addChild(accessoryViewController)
    bar.host(accessoryViewController.view)
    accessoryViewController.didMove(toParent: flutterViewController)
    
    // The accessory engine renders the bar and answers with `ready` once its handler is installed;
    // only then does it get the config it draws from.
    let accessoryChannel = FlutterMethodChannel(
      name: "cupertino_interactive_keyboard/accessory",
      binaryMessenger: engine.binaryMessenger
    )
    accessoryChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleAccessoryCall(call, result: result)
    }
    
    self.accessoryEngine = engine
    self.accessoryViewController = accessoryViewController
    self.accessoryChannel = accessoryChannel
    self.hostedAccessoryBar = bar
    KeyboardManager.shared.hostedAccessoryBar = bar
    
    // Lay the bar out once so the height handed back already reflects its real safe area.
    flutterView.layoutIfNeeded()
    result(["height": Double(bar.barHeight)])
  }
  
  /// Handles the calls of the accessory engine.
  ///
  /// The accessory app only reports what the user did in the bar; the plugin forwards it to the
  /// main engine, which owns the app's state.
  private func handleAccessoryCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    
    switch call.method {
    case "ready":
      pushAccessoryConfig()
    case "textChanged":
      channel?.invokeMethod(
        "hostedAccessoryTextChanged",
        arguments: ["text": arguments["text"] as? String ?? ""]
      )
    case "send":
      channel?.invokeMethod(
        "hostedAccessorySend",
        arguments: ["text": arguments["text"] as? String ?? ""]
      )
    default:
      return result(FlutterMethodNotImplemented)
    }
    
    result(nil)
  }
  
  /// Pushes the latest config to the accessory engine, which redraws the bar from it.
  private func pushAccessoryConfig() {
    accessoryChannel?.invokeMethod("config", arguments: accessoryConfig)
  }
  
  /// Removes the bar and destroys the engine that rendered it.
  private func tearDownHostedAccessory() {
    accessoryChannel?.setMethodCallHandler(nil)
    accessoryChannel = nil
    accessoryViewController?.willMove(toParent: nil)
    accessoryViewController?.view.removeFromSuperview()
    accessoryViewController?.removeFromParent()
    accessoryViewController = nil
    accessoryEngine?.destroyContext()
    accessoryEngine = nil
    hostedAccessoryBar?.removeFromSuperview()
    hostedAccessoryBar = nil
    accessoryConfig = [:]
    KeyboardManager.shared.hostedAccessoryBar = nil
  }
  
  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    KeyboardManager.shared.stopInteractiveTracking()
    tearDownHostedAccessory()
    scrollView.scrollabeRects = [:]
    inputView.inputAccessoryHeights = [:]
  }
  
  private func findFlutterViewController() -> FlutterViewController? {
    func checkViewController(_ viewController: UIViewController) -> FlutterViewController? {
      if
        let flutterViewController = viewController as? FlutterViewController,
        CupertinoInteractiveKeyboardPlugin.instance(for: flutterViewController) === self
      {
        return flutterViewController
      } else {
        return nil
      }
    }
    
    func findInViewController(_ viewController: UIViewController) -> FlutterViewController? {
      if let flutterViewController = checkViewController(viewController) {
        return flutterViewController
      }
      
      for child in viewController.children {
        if let flutterViewController = findInViewController(child) {
          return flutterViewController
        }
      }
      
      return nil
    }
    
    func findInWindows(_ windows: [UIWindow]) -> FlutterViewController? {
      for window in windows {
        if let flutterViewController = window.rootViewController.flatMap(findInViewController(_:)) {
          return flutterViewController
        }
      }
      return nil
    }
    
    if #available(iOS 13.0, *) {
      for case let windowScene as UIWindowScene in UIApplication.shared.connectedScenes {
        if let viewController = findInWindows(windowScene.windows) {
          return viewController
        }
      }
      return nil
    } else {
      return findInWindows(UIApplication.shared.windows)
    }
  }
}
