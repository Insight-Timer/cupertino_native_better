import Flutter
import UIKit
import SwiftUI

@available(iOS 26.0, *)
class LiquidGlassContainerPlatformView: NSObject, FlutterPlatformView {
  private let container: CNLiquidGlassHostView
  private var hostingController: UIHostingController<LiquidGlassContainerSwiftUI>
  private let channel: FlutterMethodChannel

  // Stored shape config so `applyTransitionContainment` can clip the
  // container's layer to the same rounded shape the SwiftUI glass uses.
  // Without this we clip to the rectangular layer bounds and the layer's
  // drop shadow leaks past the rounded corners — visible behind a modal
  // scrim as four square shadow nubs at the corners (Issue #36).
  private var configuredShape: String = "capsule"
  private var configuredCornerRadius: CGFloat? = nil

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(name: "CupertinoNativeLiquidGlassContainer_\(viewId)", binaryMessenger: messenger)
    self.container = CNLiquidGlassHostView(frame: frame)
    self.container.backgroundColor = .clear
    
    // Parse arguments
    var effect: String = "regular"
    var shape: String = "capsule"
    var cornerRadius: CGFloat? = nil
    var tint: UIColor? = nil
    var interactive: Bool = false
    var isDark: Bool = false
    
    if let dict = args as? [String: Any] {
      if let effectStr = dict["effect"] as? String {
        effect = effectStr
      }
      if let shapeStr = dict["shape"] as? String {
        shape = shapeStr
      }
      if let radius = dict["cornerRadius"] as? CGFloat {
        cornerRadius = radius
      }
      if let tintInt = dict["tint"] as? Int {
        tint = UIColor(
          red: CGFloat((tintInt >> 16) & 0xFF) / 255.0,
          green: CGFloat((tintInt >> 8) & 0xFF) / 255.0,
          blue: CGFloat(tintInt & 0xFF) / 255.0,
          alpha: CGFloat((tintInt >> 24) & 0xFF) / 255.0
        )
      }
      if let interactiveBool = dict["interactive"] as? Bool {
        interactive = interactiveBool
      }
      if let isDarkBool = dict["isDark"] as? Bool {
        isDark = isDarkBool
      }
    }
    
    // Create SwiftUI view
    let glassView = LiquidGlassContainerSwiftUI(
      effect: effect,
      shape: shape,
      cornerRadius: cornerRadius,
      tint: tint,
      interactive: interactive
    )

    self.hostingController = UIHostingController(rootView: glassView)
    self.hostingController.view.backgroundColor = .clear
    self.hostingController.overrideUserInterfaceStyle = isDark ? .dark : .light

    super.init()
    self.configuredShape = shape
    self.configuredCornerRadius = cornerRadius

    container.onDidMoveToWindow = { [weak self] window in
      guard window != nil else { return }
      self?.refreshGlass()
    }

    // Sync Flutter's brightness mode with Swift at initialization
    if #available(iOS 13.0, *) {
      self.hostingController.overrideUserInterfaceStyle = isDark ? .dark : .light
    }
    
    // Add hosting controller as child
    container.addSubview(hostingController.view)
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      hostingController.view.topAnchor.constraint(equalTo: container.topAnchor),
      hostingController.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      hostingController.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      hostingController.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    DispatchQueue.main.async { [weak self] in
      self?.refreshGlass()
    }
    
    // Set up method channel handler
    channel.setMethodCallHandler { [weak self] (call, result) in
      if call.method == "updateConfig" {
        self?.updateConfig(args: call.arguments)
        result(nil)
      } else if call.method == "setTransitioning" {
        let active = ((call.arguments as? [String: Any])?["active"] as? NSNumber)?.boolValue ?? false
        self?.applyTransitionContainment(active)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Toggle Issue #29 / #36 halo containment on container + hosting view.
  /// Clips with the same rounded shape the SwiftUI glass uses so the
  /// layer's drop shadow doesn't leak past the rounded corners and show
  /// up as four square shadow nubs behind a modal scrim.
  private func applyTransitionContainment(_ active: Bool) {
    if active {
      let radius = roundedCornerRadiusForCurrentShape()
      container.isOpaque = false
      container.clipsToBounds = true
      container.layer.cornerRadius = radius
      container.layer.backgroundColor = UIColor.clear.cgColor
      container.layer.shadowOpacity = 0
      hostingController.view.clipsToBounds = true
      hostingController.view.layer.cornerRadius = radius
      hostingController.view.isOpaque = false
      hostingController.view.layer.backgroundColor = UIColor.clear.cgColor
      hostingController.view.layer.shadowOpacity = 0
    } else {
      container.clipsToBounds = false
      container.layer.cornerRadius = 0
      hostingController.view.clipsToBounds = false
      hostingController.view.layer.cornerRadius = 0
    }
  }

  private func roundedCornerRadiusForCurrentShape() -> CGFloat {
    let bounds = container.bounds
    switch configuredShape {
    case "circle":
      return min(bounds.width, bounds.height) / 2.0
    case "rect":
      return configuredCornerRadius ?? 0
    default:
      // Capsule — half of the shorter side gives the iOS pill shape.
      return min(bounds.width, bounds.height) / 2.0
    }
  }
  
  private func updateConfig(args: Any?) {
    guard let dict = args as? [String: Any] else { return }
    
    var effect: String = "regular"
    var shape: String = "capsule"
    var cornerRadius: CGFloat? = nil
    var tint: UIColor? = nil
    var interactive: Bool = false
    var isDark: Bool = false
    
    if let effectStr = dict["effect"] as? String {
      effect = effectStr
    }
    if let shapeStr = dict["shape"] as? String {
      shape = shapeStr
    }
    if let radius = dict["cornerRadius"] as? CGFloat {
      cornerRadius = radius
    }
    if let tintInt = dict["tint"] as? Int {
      tint = UIColor(
        red: CGFloat((tintInt >> 16) & 0xFF) / 255.0,
        green: CGFloat((tintInt >> 8) & 0xFF) / 255.0,
        blue: CGFloat(tintInt & 0xFF) / 255.0,
        alpha: CGFloat((tintInt >> 24) & 0xFF) / 255.0
      )
    }
    if let interactiveBool = dict["interactive"] as? Bool {
      interactive = interactiveBool
    }
    if let isDarkBool = dict["isDark"] as? Bool {
      isDark = isDarkBool
    }
    
    // Update the SwiftUI view
    let newGlassView = LiquidGlassContainerSwiftUI(
      effect: effect,
      shape: shape,
      cornerRadius: cornerRadius,
      tint: tint,
      interactive: interactive
    )

    hostingController.rootView = newGlassView
    hostingController.overrideUserInterfaceStyle = isDark ? .dark : .light
    // Keep stored config in sync for `applyTransitionContainment`.
    self.configuredShape = shape
    self.configuredCornerRadius = cornerRadius
    refreshGlass()
  }

  private func refreshGlass() {
    hostingController.rootView = hostingController.rootView
    container.setNeedsLayout()
    hostingController.view.setNeedsLayout()
    container.layoutIfNeeded()
    hostingController.view.layoutIfNeeded()
  }
  
  func view() -> UIView {
    return container
  }
}

@available(iOS 26.0, *)
struct LiquidGlassContainerSwiftUI: View {
  let effect: String
  let shape: String
  let cornerRadius: CGFloat?
  let tint: UIColor?
  let interactive: Bool

  var body: some View {
    GeometryReader { geometry in
      shapeForConfig()
        .fill(Color.clear)
        .contentShape(shapeForConfig())
        .allowsHitTesting(false)  // Always false - let Flutter handle gestures
        .glassEffect(glassEffectForConfig(), in: shapeForConfig())
        .frame(width: geometry.size.width, height: geometry.size.height)
    }
  }
  
  private func glassEffectForConfig() -> Glass {
    var glass: Glass
    switch effect {
    case "clear":
      glass = Glass.clear
    default:
      glass = Glass.regular
    }

    if let tintColor = tint {
      glass = glass.tint(Color(tintColor))
    }

    if interactive {
      glass = glass.interactive()
    }

    return glass
  }
  
  private func shapeForConfig() -> some Shape {
    switch shape {
    case "rect":
      if let radius = cornerRadius {
        return AnyShape(RoundedRectangle(cornerRadius: radius))
      }
      return AnyShape(RoundedRectangle(cornerRadius: 0))
    case "circle":
      return AnyShape(Circle())
    default: // capsule
      return AnyShape(Capsule())
    }
  }
}

// Fallback for iOS < 26
class FallbackLiquidGlassContainerView: NSObject, FlutterPlatformView {
  private let container: UIView

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.container = UIView(frame: frame)
    self.container.backgroundColor = .clear
    super.init()
  }

  func view() -> UIView {
    return container
  }
}

private final class CNLiquidGlassHostView: UIView {
  var onDidMoveToWindow: ((UIWindow?) -> Void)?

  override func didMoveToWindow() {
    super.didMoveToWindow()
    onDidMoveToWindow?(window)
  }
}
