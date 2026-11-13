import Flutter
import UIKit

public class CupertinoInteractiveKeyboardPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    _ = KeyboardManager.shared
    swizzleFlutterViewController()
    swizzleFlutterTextInputView()
    swizzleFlutterViewHitTest()
    
    let channel = FlutterMethodChannel(name: "cupertino_interactive_keyboard", binaryMessenger: registrar.messenger())
    let instance = CupertinoInteractiveKeyboardPlugin()
    instance.channel = channel
    CIKTrace.sink = { [weak instance] line in
      instance?.channel?.invokeMethod("trace", arguments: ["line": line])
    }
    // The app can react to the interactive drag itself, not only to the inset changing.
    KeyboardManager.shared.onKeyboardDraggingChanged = { [weak instance] dragging in
      instance?.channel?.invokeMethod("keyboardDragging", arguments: ["dragging": dragging])
      instance?.forwardKeyboardDraggingToHosted(dragging)
    }
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
  private var hostedSurface: CIKHostedSurface?
  /// A surface rectangle that arrived while the keyboard was being dragged; applied on settle.
  private var pendingSurfaceRect: CGRect?
  /// The hidden scroll view that drives the interactive dismissal for a behind surface.
  private weak var surfaceDismissScrollView: CIKScrollView?
  /// The main view's opacity before a behind surface made it non-opaque.
  private var savedViewOpaque: Bool?
  /// The view controller whose opacity a behind surface changed.
  private weak var savedViewOpaqueViewController: FlutterViewController?
  /// The id of the hosted thing, so a displaced widget can tell it was the one released.
  private var hostedThingId: Int?
  private var accessoryChannel: FlutterMethodChannel?
  private var accessoryEngine: FlutterEngine?
  private var accessoryViewController: FlutterViewController?
  private var engineGroup: FlutterEngineGroup?
  /// Whether the accessory app installed its channel handler and can receive messages.
  private var accessoryReady = false
  /// Messages sent to the accessory before it was ready, flushed in order on `ready`.
  private var pendingAccessoryInvocations: [[String: Any]] = []
    
  override init() {
    super.init()
  }
  
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setTraceEnabled":
      guard let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool else {
        return result(FlutterMethodNotImplemented)
      }
      CIKTrace.setEnabled(enabled)
      result(nil)

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
      guard let config = NativeAccessoryConfig(arguments: call.arguments) else {
        return result(FlutterMethodNotImplemented)
      }
      
      DispatchQueue.main.async {
        self.createHostedAccessory(config, result: result)
      }
      
    case "setHostedSurfaceInteractive":
      guard
        let args = call.arguments as? [String: Any],
        let interactive = args["interactive"] as? Bool
      else {
        return result(FlutterMethodNotImplemented)
      }

      DispatchQueue.main.async {
        KeyboardManager.shared.hostedSurfaceInteractive = interactive
        CIKTrace.log("hosted", "surface interactive=" + String(interactive))
        result(nil)
      }

    case "updateHostedAccessoryRect":
      guard
        let args = call.arguments as? [String: Any],
        let rectMap = args["rect"] as? [String: Any],
        let rect = CupertinoInteractiveKeyboardPlugin.rect(from: rectMap)
      else {
        return result(FlutterMethodNotImplemented)
      }

      DispatchQueue.main.async {
        self.updateHostedSurfaceRect(rect)
        result(nil)
      }

    case "updateHostedAccessoryHeight":
      guard
        let args = call.arguments as? [String: Any],
        let height = args["height"] as? NSNumber
      else {
        return result(FlutterMethodNotImplemented)
      }
      
      DispatchQueue.main.async {
        self.hostedAccessoryBar?.apply(height: CGFloat(height.doubleValue))
        result(nil)
      }

    case "setHostedSurfaceAlpha":
      guard
        let args = call.arguments as? [String: Any],
        let alpha = args["alpha"] as? NSNumber
      else {
        return result(FlutterMethodNotImplemented)
      }

      DispatchQueue.main.async {
        // A native opacity: the hosted engine keeps its already-rendered
        // pixels, and Core Animation composites the app's fade for free. A
        // behind surface must stay opaque: its translucency would break the
        // hole the app paints over it.
        if let surface = self.hostedSurface, !surface.isBehind {
          surface.alpha = CGFloat(alpha.doubleValue)
        }
        result(nil)
      }

    case "updateHostedSurfaceContentHeight":
      guard
        let args = call.arguments as? [String: Any],
        let height = args["height"] as? NSNumber
      else {
        return result(FlutterMethodNotImplemented)
      }

      DispatchQueue.main.async {
        self.updateHostedSurfaceContentHeight(CGFloat(height.doubleValue))
        result(nil)
      }

    case "updateHostedAccessoryHidden":
      guard
        let args = call.arguments as? [String: Any],
        let hidden = args["hidden"] as? Bool
      else {
        return result(FlutterMethodNotImplemented)
      }

      DispatchQueue.main.async {
        self.updateHostedAccessoryHidden(hidden)
        result(nil)
      }

    case "invokeHostedAccessory":
      guard
        let args = call.arguments as? [String: Any],
        let method = args["method"] as? String
      else {
        return result(FlutterMethodNotImplemented)
      }
      let message: [String: Any] = [
        "method": method,
        "arguments": args["arguments"] ?? NSNull(),
      ]
      
      DispatchQueue.main.async {
        self.invokeHostedAccessory(message)
        result(nil)
      }
      
    case "removeHostedAccessory":
      let id = ((call.arguments as? [String: Any])?["id"] as? NSNumber)?.intValue
      DispatchQueue.main.async {
        self.removeHostedAccessory(id: id)
        result(nil)
      }
      
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  /// Creates the hosted accessory bar: a container glued to the keyboard layout guide, with a
  /// second Flutter engine rendering the app's accessory entrypoint inside it.
  ///
  /// `keyboardLayoutGuide` is iOS 15+, while the plugin's floor is iOS 13: on older systems the
  /// method returns nil and the Flutter widget keeps its own placeholder.
  private func createHostedAccessory(
    _ config: NativeAccessoryConfig,
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

    // A behind surface is a sibling of the Flutter view; without a superview there is nowhere to
    // put it and the previous host must not be torn down for a transient condition.
    if config.behind {
      guard config.rect != nil, flutterViewController.view.superview != nil else {
        return result(FlutterMethodNotImplemented)
      }
    }

    if let rect = config.rect {
      createHostedSurface(config, rect: rect, flutterViewController: flutterViewController, result: result)
      return
    }

    announceReleasedHostedThing()
    tearDownHostedAccessory()

    let bar = CIKHostedAccessoryBar(config: config)
    // The bar's own view stays transparent: the accessory engine draws the app's bar, and
    // whatever the app paints behind it (or leaves unpainted) has to stay visible. An app that
    // wants an opaque bar paints it inside its accessory widget.
    bar.backgroundColor = .clear
    bar.isHidden = config.hidden
    let flutterView = flutterViewController.view!
    flutterView.addSubview(bar)
    // The layout guide is only a live delta source during drags now, but it must rest on the view's
    // bottom edge like the bar does: on iOS 17+ its default resting position is the safe-area bottom,
    // 34 pt above.
    if #available(iOS 17.0, *) {
      flutterView.keyboardLayoutGuide.usesBottomSafeArea = false
    }
    // The plugin owns the bar's position: the manager holds the inset from the view's bottom and
    // animates it with each keyboard notification. The bar is created where the keyboard currently
    // is, which the manager knows from the last notification (or 0 when the keyboard is closed).
    let initialInset: CGFloat
    if KeyboardManager.shared.currentBarInset > 0.5 {
      initialInset = KeyboardManager.shared.currentBarInset
    } else if #available(iOS 15.0, *) {
      // The bar can be created while the keyboard is already up and no notification has reached the
      // manager yet; the guide is then the only reading of the keyboard's position. It rests on the
      // view's bottom edge when the keyboard is closed, so a small reading is the home indicator,
      // not a keyboard.
      flutterView.layoutIfNeeded()
      let guideTop = flutterView.keyboardLayoutGuide.layoutFrame.minY
      let guideInset = flutterView.bounds.maxY - guideTop
      initialInset = guideInset > 50 ? min(guideInset, flutterView.bounds.maxY) : 0
    } else {
      initialInset = 0
    }
    bar.attach(to: flutterView, bottomInset: initialInset)
    bar.contentPadding = initialInset <= 0.5 ? bar.restingPadding : 0
    KeyboardManager.shared.trackBarInset(initialInset)
    
    bar.onHeightChange = { [weak self] height, duration, curve in
      self?.channel?.invokeMethod("hostedAccessoryHeight", arguments: [
        "height": Double(height),
        "duration": duration,
        "curve": curve,
      ])
    }
    
    let hosted = makeHostedEngine(config)
    flutterViewController.addChild(hosted.viewController)
    bar.host(hosted.viewController.view)
    hosted.viewController.didMove(toParent: flutterViewController)
    
    self.accessoryEngine = hosted.engine
    self.accessoryViewController = hosted.viewController
    self.accessoryChannel = hosted.channel
    self.hostedAccessoryBar = bar
    self.hostedSurface = nil
    self.hostedThingId = config.id
    // The bar is the inset driver's band even while hidden: it is still laid out and positioned, and
    // an app whose bar is hidden has to position its own composer with the inset alone.
    KeyboardManager.shared.hostedBand = bar
    KeyboardManager.shared.hostedSurfaceViewController = nil
    KeyboardManager.shared.hostedSurfaceView = nil
    KeyboardManager.shared.hostedSurfaceInteractive = false
    KeyboardManager.shared.publishesInsetToEngine = true
    
    // Lay the bar out once so the height handed back already reflects its real safe area.
    flutterView.layoutIfNeeded()
    CIKTrace.log(
      "hosted",
      "create height=" + CIKTrace.points(config.height)
        + " hidden=" + String(config.hidden)
        + " barHeight=" + CIKTrace.points(bar.barHeight)
    )
    result(["height": Double(bar.barHeight)])
  }
  
  /// Creates the second engine that renders the hosted bar or surface.
  ///
  /// Both modes share the engine, the transparent view and the bridge channel; only the container
  /// they are put into differs.
  private func makeHostedEngine(
    _ config: NativeAccessoryConfig
  ) -> (engine: FlutterEngine, viewController: FlutterViewController, channel: FlutterMethodChannel) {
    let project = FlutterDartProject()
    let group = engineGroup
      ?? FlutterEngineGroup(name: "cupertino_interactive_keyboard.accessory", project: project)
    engineGroup = group
    // The hosted thing is a single screen, not a routed app: the engine must not inherit the app's
    // launch route (deep link, `flutter run --route`), which its MaterialApp would then fail to
    // navigate to.
    let engine = group.makeEngine(
      withEntrypoint: config.entrypoint,
      libraryURI: config.libraryURI,
      initialRoute: "/"
    )

    let accessoryViewController = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    // The hosted engine's view is transparent too, so it only shows the pixels its Flutter app
    // actually paints: the app behind the bar or the surface keeps showing through.
    accessoryViewController.isViewOpaque = false
    accessoryViewController.view.backgroundColor = .clear

    // The hosted engine renders the app's content and answers with `ready` once its handler is
    // installed; messages sent before that are queued and flushed then.
    let accessoryChannel = FlutterMethodChannel(
      name: "cupertino_interactive_keyboard/accessory",
      binaryMessenger: engine.binaryMessenger
    )
    accessoryChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleAccessoryCall(call, result: result)
    }

    return (engine, accessoryViewController, accessoryChannel)
  }

  /// Creates the hosted surface: the whole content area above the keyboard in a second engine.
  ///
  /// The surface container clips a fixed-size engine view that is moved by a transform; the
  /// rectangle the app reports decides the container's top and the engine view's height (the
  /// safe-area bottom is excluded, so the hosted engine's safe area never changes).
  ///
  /// A behind surface gets its own hidden scroll view inside the container: the surface is a
  /// sibling of the Flutter view, so the Flutter view's interactive-dismissal recognizers never see
  /// drags that land on it. The container's scroll view drives the same UIKit interactive dismissal
  /// for those touches.
  private func createHostedSurface(
    _ config: NativeAccessoryConfig,
    rect: CGRect,
    flutterViewController: FlutterViewController,
    result: @escaping FlutterResult
  ) {
    announceReleasedHostedThing()
    tearDownHostedAccessory()

    let hosted = makeHostedEngine(config)
    let flutterView = flutterViewController.view!
    flutterView.layoutIfNeeded()
    let safeBottom = flutterView.safeAreaInsets.bottom

    let surface = CIKHostedSurface()
    surface.isBehind = config.behind
    surface.isHidden = config.hidden
    // A forward surface the app sizes once: its engine view never changes size, the reported
    // rectangle's top only clips it. Behind mode never resizes either, for a different reason.
    var contentBottomInset: CGFloat = 0
    let contentHeight: CGFloat
    if config.behind {
      // Behind mode: the surface goes below the Flutter view and covers it, so the app can paint a
      // transparent hole over it and keep its overlays above the live list. The engine view never
      // resizes; the keyboard translates it.
      guard let parent = flutterView.superview else {
        return result(nil)
      }
      // Insert first, then constrain: the surface is a sibling of the Flutter view, and constraints
      // between the two need a common ancestor before they are activated.
      parent.insertSubview(surface, belowSubview: flutterView)
      surface.attach(to: flutterView, top: 0, safeAreaBottom: 0)
      contentHeight = flutterView.bounds.height
      surface.holeRect = rect
      // The Flutter layer must be non-opaque for the surface to show through the hole. An app that
      // relies on behind mode should set this before the first frame; this is the safety net.
      savedViewOpaque = flutterViewController.isViewOpaque
      savedViewOpaqueViewController = flutterViewController
      flutterViewController.isViewOpaque = false
      KeyboardManager.shared.hostedSurfaceInteractive = false
      KeyboardManager.shared.hostedSurfaceFlutterView = flutterView
    } else {
      flutterView.addSubview(surface)
      surface.attach(to: flutterView, top: rect.minY, safeAreaBottom: safeBottom)
      if let fixedRectHeight = config.contentHeight {
        // The app animates this surface's rectangle (a sliding panel): size the engine view once
        // from the height it has when fully revealed and let the rectangle clip it.
        contentBottomInset = safeBottom
        contentHeight = KeyboardGeometry.fixedSurfaceContentHeight(
          rectHeight: fixedRectHeight,
          safeAreaBottom: safeBottom
        )
      } else {
        contentHeight = CIKHostedSurface.contentHeight(
          parentHeight: flutterView.bounds.height,
          top: rect.minY,
          safeAreaBottom: safeBottom
        )
      }
    }

    flutterViewController.addChild(hosted.viewController)
    surface.host(
      hosted.viewController.view,
      contentHeight: contentHeight,
      fixedRectHeight: config.contentHeight,
      contentBottomInset: contentBottomInset
    )
    hosted.viewController.didMove(toParent: flutterViewController)
    flutterView.layoutIfNeeded()

    if config.behind {
      // Drags on the surface never reach the Flutter view's recognizers (the surface is a sibling
      // below it), so the surface carries its own hidden scroll view whose pan drives UIKit's
      // interactive keyboard dismissal, exactly like the main one does for main-engine touches.
      let dismiss = CIKScrollView()
      dismiss.frame = surface.bounds
      dismiss.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      dismiss.scrollabeRects = [0: rect]
      surface.addSubview(dismiss)
      self.surfaceDismissScrollView = dismiss
      CIKTrace.log("hosted", "surface dismiss scroll view installed")
    }

    self.accessoryEngine = hosted.engine
    self.accessoryViewController = hosted.viewController
    self.accessoryChannel = hosted.channel
    self.hostedAccessoryBar = nil
    self.hostedSurface = surface
    self.pendingSurfaceRect = nil
    self.hostedThingId = config.id

    KeyboardManager.shared.hostedBand = config.hidden ? nil : surface
    KeyboardManager.shared.hostedSurfaceViewController = hosted.viewController
    KeyboardManager.shared.hostedSurfaceView = surface
    KeyboardManager.shared.publishesInsetToEngine = false
    KeyboardManager.shared.onTrackingStopped = { [weak self] in
      self?.applyPendingSurfaceRect()
    }
    let inset = KeyboardManager.shared.currentBarInset
    surface.apply(
      inset: inset,
      padding: config.behind ? 0 : max(0, safeBottom - inset),
      animated: false,
      duration: 0,
      curve: 0
    )

    CIKTrace.log(
      "hosted",
      "surface top=" + CIKTrace.points(rect.minY)
        + " height=" + CIKTrace.points(contentHeight)
        + " inset=" + CIKTrace.points(inset)
        + " hidden=" + String(config.hidden)
        + " behind=" + String(config.behind)
        + " fixed=" + String(config.contentHeight != nil)
        + " content=" + CIKTrace.points(contentHeight)
    )
    result(["height": Double(contentHeight)])
  }

  /// Changes the size a fixed-content surface keeps, from a rectangle height.
  ///
  /// Only a rotation or an app bar cap change gets here: the rectangle the app animates during a
  /// panel drag never resizes the hosted engine.
  private func updateHostedSurfaceContentHeight(_ rectHeight: CGFloat) {
    guard
      let surface = hostedSurface,
      !surface.isBehind,
      let flutterView = KeyboardManager.shared.flutterViewController?.view
    else {
      return
    }
    flutterView.layoutIfNeeded()
    surface.updateContentRectHeight(
      rectHeight,
      safeAreaBottom: flutterView.safeAreaInsets.bottom
    )
    flutterView.layoutIfNeeded()
    CIKTrace.log(
      "hosted",
      "surface content=" + CIKTrace.points(surface.contentHeight)
    )
  }

  /// Applies a surface rectangle, or defers it while the keyboard is being dragged.
  ///
  /// A rectangle change mid-drag would resize the hosted engine and re-lay the content out on a
  /// frame that is already in flight - the very lag the surface exists to remove.
  private func updateHostedSurfaceRect(_ rect: CGRect) {
    guard let surface = hostedSurface else { return }
    // A behind surface only stores the hole and the passthrough rectangle; its engine view never
    // resizes, so the update can never land on an in-flight frame and does not need deferring.
    if surface.isBehind {
      applySurfaceRect(rect)
      return
    }
    if KeyboardManager.shared.isTrackingKeyboard {
      pendingSurfaceRect = rect
      return
    }
    applySurfaceRect(rect)
  }

  private func applyPendingSurfaceRect() {
    guard pendingSurfaceRect != nil else { return }
    // The gesture may have been released; let the keyboard's release animation finish before the
    // hosted engine is resized, so no metrics push lands while the surface is still moving.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self, let rect = self.pendingSurfaceRect else { return }
      // A new drag started meanwhile: keep the rectangle pending for the next settle.
      if KeyboardManager.shared.isTrackingKeyboard { return }
      self.pendingSurfaceRect = nil
      self.applySurfaceRect(rect)
    }
  }

  private func applySurfaceRect(_ rect: CGRect) {
    guard
      let surface = hostedSurface,
      let flutterView = KeyboardManager.shared.flutterViewController?.view
    else {
      return
    }
    if surface.isBehind {
      // The engine view covers the screen and never resizes during a drag; only the hole the app
      // paints and the passthrough rectangle move. Do NOT re-apply the inset here: the manager owns
      // the transform, and a model write during a keyboard animation would snap the list.
      surface.holeRect = rect
      surfaceDismissScrollView?.scrollabeRects = [0: rect]
      let viewHeight = KeyboardManager.shared.hostedSurfaceFlutterView?.bounds.height
      if let viewHeight, viewHeight > 0 {
        surface.updateContentHeight(viewHeight)
      }
      return
    }
    flutterView.layoutIfNeeded()
    let safeBottom = flutterView.safeAreaInsets.bottom
    surface.update(
      top: rect.minY,
      safeAreaBottom: safeBottom,
      parentHeight: flutterView.bounds.height
    )
    let inset = KeyboardManager.shared.currentBarInset
    surface.apply(
      inset: inset,
      padding: max(0, safeBottom - inset),
      animated: false,
      duration: 0,
      curve: 0
    )
    flutterView.layoutIfNeeded()
    CIKTrace.log(
      "hosted",
      "surface rect top=" + CIKTrace.points(rect.minY)
        + " height=" + CIKTrace.points(surface.bounds.height)
    )
  }

  /// Tells the main isolate that the hosted thing it owns is about to be replaced.
  ///
  /// The new Dart widget may be created while the previous one is still mounted (a route pushed
  /// over another); that widget must know its engine is gone so it can re-host when it is visible
  /// again instead of showing a blank area.
  private func announceReleasedHostedThing() {
    guard hostedAccessoryBar != nil || hostedSurface != nil else { return }
    channel?.invokeMethod(
      "hostedAccessoryReleased",
      arguments: ["id": hostedThingId ?? -1]
    )
  }

  /// Forwards the interactive drag state to the hosted app, so it can pin its scroll offset: the
  /// surface itself already moves the content, and letting the list scroll too would double it.
  private func forwardKeyboardDraggingToHosted(_ dragging: Bool) {
    guard hostedSurface != nil else { return }
    invokeHostedAccessory([
      "method": "keyboardDragging",
      "arguments": ["dragging": dragging],
    ])
  }

  private static func rect(from map: [String: Any]) -> CGRect? {
    guard
      let x = (map["x"] as? NSNumber)?.doubleValue,
      let y = (map["y"] as? NSNumber)?.doubleValue,
      let width = (map["width"] as? NSNumber)?.doubleValue,
      let height = (map["height"] as? NSNumber)?.doubleValue
    else {
      return nil
    }
    return CGRect(x: x, y: y, width: width, height: height)
  }

  /// Handles the calls of the accessory engine.
  ///
  /// The accessory app only signals that it is ready and forwards the messages it sends; the
  /// plugin hands both to the main engine, which owns the app's state.
  private func handleAccessoryCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    
    switch call.method {
    case "contentHeight":
      guard let height = (arguments["height"] as? NSNumber)?.doubleValue else {
        return result(FlutterMethodNotImplemented)
      }
      DispatchQueue.main.async {
        self.hostedAccessoryBar?.apply(height: CGFloat(height))
      }
    case "ready":
      accessoryReady = true
      // The main isolate can invoke before the accessory app exists; deliver those now, in order.
      let pending = pendingAccessoryInvocations
      pendingAccessoryInvocations = []
      for message in pending {
        accessoryChannel?.invokeMethod("invoke", arguments: message)
      }
      channel?.invokeMethod("hostedAccessoryReady", arguments: [String: Any]())
    case "invoke":
      guard let method = arguments["method"] as? String else {
        return result(FlutterMethodNotImplemented)
      }
      channel?.invokeMethod(
        "hostedAccessoryInvoke",
        arguments: [
          "method": method,
          "arguments": arguments["arguments"] ?? NSNull(),
        ]
      )
    default:
      return result(FlutterMethodNotImplemented)
    }
    
    result(nil)
  }
  
  /// Shows or hides the bar without tearing its engine down.
  ///
  /// Hiding only skips drawing and hit-testing, so the accessory app keeps its state and showing
  /// it again costs a frame. The bar keeps being the keyboard band the inset driver follows: a
  /// hidden view still lays out, so its frame and the inset driver still follow the keyboard.
  private func updateHostedAccessoryHidden(_ hidden: Bool) {
    if let surface = hostedSurface, let viewController = accessoryViewController {
      // The hosted app must drop focus before the view is hidden: a hidden view keeps first
      // responder and the keyboard would stay up over whatever covers the surface.
      invokeHostedAccessory(["method": "hidden", "arguments": ["hidden": hidden]])
      surface.isHidden = hidden
      if hidden {
        viewController.view.endEditing(true)
        KeyboardManager.shared.stopInteractiveTracking()
        KeyboardManager.shared.hostedBand = nil
      } else {
        let inset = KeyboardManager.shared.currentBarInset
        KeyboardManager.shared.hostedBand = surface
        // Showing again can happen while the keyboard is still animating; follow it with the
        // keyboard's curve instead of snapping the surface into place.
        surface.apply(
          inset: inset,
          padding: max(0, surface.restingPadding - inset),
          animated: true,
          duration: 0.25,
          curve: 7
        )
      }
      CIKTrace.log("hosted", "surface hidden=" + String(hidden))
      return
    }
    hostedAccessoryBar?.isHidden = hidden
    // A hidden bar keeps being the live band: it still lays out, and while the bar is hidden the app
    // positions its own composer with the inset alone.
    KeyboardManager.shared.hostedBand = hostedAccessoryBar
    CIKTrace.log("hosted", "hidden=" + String(hidden))
  }

  /// Removes the hosted thing, but only when [id] is nil or names the current host.
  ///
  /// A widget that unmounts while its engine is still starting must not tear down whatever host a
  /// newer widget created in that window.
  private func removeHostedAccessory(id: Int?) {
    if let id, let hostedThingId, id != hostedThingId {
      CIKTrace.log(
        "hosted",
        "remove ignored id=" + String(id) + " current=" + String(hostedThingId)
      )
      return
    }
    tearDownHostedAccessory()
  }

  /// Sends a message to the accessory app, queueing it until the app reported `ready`.
  private func invokeHostedAccessory(_ message: [String: Any]) {
    guard accessoryReady else {
      pendingAccessoryInvocations.append(message)
      return
    }
    
    accessoryChannel?.invokeMethod("invoke", arguments: message)
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
    surfaceDismissScrollView?.removeFromSuperview()
    surfaceDismissScrollView = nil
    hostedSurface?.removeFromSuperview()
    hostedSurface = nil
    pendingSurfaceRect = nil
    hostedThingId = nil
    accessoryReady = false
    pendingAccessoryInvocations = []
    KeyboardManager.shared.hostedBand = nil
    KeyboardManager.shared.hostedSurfaceViewController = nil
    KeyboardManager.shared.hostedSurfaceView = nil
    KeyboardManager.shared.hostedSurfaceFlutterView = nil
    KeyboardManager.shared.hostedSurfaceInteractive = false
    KeyboardManager.shared.publishesInsetToEngine = true
    KeyboardManager.shared.onTrackingStopped = nil
    if let saved = savedViewOpaque {
      let owner = savedViewOpaqueViewController
        ?? KeyboardManager.shared.flutterViewController
        ?? findFlutterViewController()
      owner?.isViewOpaque = saved
      if owner != nil {
        savedViewOpaque = nil
      }
      savedViewOpaqueViewController = nil
    }
    CIKTrace.log("hosted", "tear down")
  }
  
  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    KeyboardManager.shared.onKeyboardDraggingChanged = nil
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
