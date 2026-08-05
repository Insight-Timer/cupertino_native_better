import Flutter
import UIKit

/// Renders the glass with UIKit's own `UIGlassEffect` inside a `UIVisualEffectView`.
///
/// This used to host a SwiftUI `Capsule().glassEffect(...)` in a `UIHostingController`. The material was
/// right, but a hosting controller runs SwiftUI's layout pass inside the Flutter-hosted view, and the
/// `GeometryReader` the body needed re-evaluated whenever geometry was read — so scrolling content behind
/// the glass drove that work every frame, on the platform thread. `CupertinoTabBarPlatformView` never had
/// the problem because it is plain UIKit (a real `UITabBar`), which is what pointed at the hosting
/// controller rather than at the glass. `UIVisualEffectView` composites the same material with no SwiftUI
/// in the path.
@available(iOS 26.0, *)
class LiquidGlassContainerPlatformView: NSObject, FlutterPlatformView {
  private let container: CNLiquidGlassHostView
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.channel = FlutterMethodChannel(name: "CupertinoNativeLiquidGlassContainer_\(viewId)", binaryMessenger: messenger)
    self.container = CNLiquidGlassHostView(frame: frame)
    super.init()

    container.apply(Self.parse(args))

    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "updateConfig":
        self.container.apply(Self.parse(call.arguments))
        result(nil)
      case "setTransitioning":
        let active = ((call.arguments as? [String: Any])?["active"] as? NSNumber)?.boolValue ?? false
        self.container.setTransitionContainment(active)
        result(nil)
      case "setInteractive":
        if let args = call.arguments as? [String: Any],
           let interactive = (args["interactive"] as? NSNumber)?.boolValue {
          self.container.setInteractive(interactive)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView {
    return container
  }

  /// Same argument contract as the Dart side has always sent.
  private static func parse(_ args: Any?) -> CNLiquidGlassConfig {
    var config = CNLiquidGlassConfig()
    guard let dict = args as? [String: Any] else { return config }
    if let effect = dict["effect"] as? String { config.effect = effect }
    if let shape = dict["shape"] as? String { config.shape = shape }
    if let radius = dict["cornerRadius"] as? CGFloat { config.cornerRadius = radius }
    if let tint = dict["tint"] as? Int {
      config.tint = UIColor(
        red: CGFloat((tint >> 16) & 0xFF) / 255.0,
        green: CGFloat((tint >> 8) & 0xFF) / 255.0,
        blue: CGFloat(tint & 0xFF) / 255.0,
        alpha: CGFloat((tint >> 24) & 0xFF) / 255.0
      )
    }
    if let interactive = dict["interactive"] as? Bool { config.interactive = interactive }
    if let isDark = dict["isDark"] as? Bool { config.isDark = isDark }
    return config
  }
}

/// The parsed `LiquidGlassConfig` from Dart.
@available(iOS 26.0, *)
private struct CNLiquidGlassConfig {
  var effect: String = "regular"
  var shape: String = "capsule"
  var cornerRadius: CGFloat? = nil
  var tint: UIColor? = nil
  var interactive: Bool = false
  var isDark: Bool = false
}

/// Hosts the effect view and keeps its corner radius in step with the shape, which for a capsule depends
/// on the bounds Flutter gives us and so has to be resolved on every layout.
@available(iOS 26.0, *)
private final class CNLiquidGlassHostView: UIView {
  private let effectView = UIVisualEffectView()
  private var config = CNLiquidGlassConfig()

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    layer.cornerCurve = .continuous
    // Flutter owns the gestures; the glass is decoration. `setInteractive` can hand it back.
    isUserInteractionEnabled = false
    effectView.isUserInteractionEnabled = false
    effectView.clipsToBounds = true
    effectView.layer.cornerCurve = .continuous
    effectView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(effectView)
    NSLayoutConstraint.activate([
      effectView.topAnchor.constraint(equalTo: topAnchor),
      effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
      effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
      effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// The effect is re-applied once there is a window. Upstream did the same (`onDidMoveToWindow` plus a
  /// deferred refresh) because the glass could come up unrendered on the first frame otherwise; it costs
  /// one effect assignment per attach.
  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard window != nil else { return }
    apply(config)
  }

  func apply(_ config: CNLiquidGlassConfig) {
    self.config = config

    let glass = UIGlassEffect(style: config.effect == "clear" ? .clear : .regular)
    glass.tintColor = config.tint
    glass.isInteractive = config.interactive
    effectView.effect = glass

    // Follow the app theme rather than the device, so the forced-dark Timer tab renders a dark bar.
    effectView.overrideUserInterfaceStyle = config.isDark ? .dark : .light

    setNeedsLayout()
  }

  func setInteractive(_ interactive: Bool) {
    isUserInteractionEnabled = interactive
    effectView.isUserInteractionEnabled = interactive
  }

  /// Clips to the glass's own shape while a Flutter modal is up, so the layer's shadow cannot leak past
  /// the rounded corners and show as square nubs behind the scrim (upstream issues #29 / #36).
  func setTransitionContainment(_ active: Bool) {
    clipsToBounds = active
    layer.cornerRadius = active ? cornerRadiusForShape() : 0
    if active {
      layer.backgroundColor = UIColor.clear.cgColor
      layer.shadowOpacity = 0
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    effectView.layer.cornerRadius = cornerRadiusForShape()
    if clipsToBounds { layer.cornerRadius = cornerRadiusForShape() }
  }

  private func cornerRadiusForShape() -> CGFloat {
    switch config.shape {
    case "rect":
      return config.cornerRadius ?? 0
    case "circle":
      return min(bounds.width, bounds.height) / 2.0
    default:
      // Capsule — half the shorter side gives the iOS pill.
      return min(bounds.width, bounds.height) / 2.0
    }
  }
}

// Fallback for iOS < 26.
//
// Must register a MethodChannel no-op handler so Dart-side calls like
// setTransitioning (Issue #29 halo containment) and setInteractive
// (ModalHideMixin) don't throw MissingPluginException. Same fix as the
// CupertinoGlassButtonGroup fallback.
class FallbackLiquidGlassContainerView: NSObject, FlutterPlatformView {
  private let container: UIView
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    self.container = UIView(frame: frame)
    self.container.backgroundColor = .clear
    self.channel = FlutterMethodChannel(
      name: "CupertinoNativeLiquidGlassContainer_\(viewId)",
      binaryMessenger: messenger
    )
    super.init()
    self.channel.setMethodCallHandler { _, result in result(nil) }
  }

  func view() -> UIView {
    return container
  }
}
