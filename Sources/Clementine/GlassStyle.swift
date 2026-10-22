import AppKit
import SwiftUI
import QuartzCore

enum GlassRendering {
    // Window-server backdrop effects cannot be cached into an offscreen bitmap.
    // Static previews approximate their tint; the running app uses native glass.
    static var isStaticPreview: Bool { CommandLine.arguments.contains("--snapshot") }
}
final class PassiveSurfaceView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Native backdrop surfaces remain transparent to dragging and pointer events.
@available(macOS 26.0, *)
final class PassiveGlassView: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
final class PassiveMaterialView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
@MainActor enum GlassStyle {
    static func surface(frame: NSRect, tint: NSColor, radius: CGFloat) -> NSView {
        if GlassRendering.isStaticPreview {
            let surface = PassiveSurfaceView(frame:frame)
            surface.wantsLayer = true
            surface.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.4).cgColor
            surface.layer?.cornerRadius = radius
            return surface
        }
        if #available(macOS 26.0, *) {
            let glass = PassiveGlassView(frame: frame)
            glass.style = .regular
            glass.tintColor = tint
            glass.cornerRadius = radius
            glass.wantsLayer = true
            return glass
        }
        let material = PassiveMaterialView(frame: frame)
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = radius
        material.layer?.masksToBounds = true
        return material
    }
}
struct OrangeGlassBackdrop: View {
    var body: some View {
        ZStack {
            if GlassRendering.isStaticPreview { Color(red:1,green:0.97,blue:0.92) }
            else { Rectangle().fill(.ultraThinMaterial) }
            LinearGradient(colors: [Color(red:1,green:0.91,blue:0.77).opacity(0.9), Color(red:1,green:0.97,blue:0.93).opacity(0.65), orange.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { geometry in
                Circle().fill(RadialGradient(colors:[orange.opacity(0.14),.clear],center:.center,startRadius:0,endRadius:geometry.size.width*0.45)).frame(width:geometry.size.width*0.9).offset(x:geometry.size.width*0.48,y:-220)
            }.clipped()
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}
struct SidebarGlassBackground: View {
    var body: some View {
        if GlassRendering.isStaticPreview { Color(red:1,green:0.92,blue:0.81).opacity(0.7) }
        else { Rectangle().fill(.ultraThinMaterial).overlay(orange.opacity(0.055)) }
    }
}
private struct ClementineGlassModifier: ViewModifier {
    var radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if GlassRendering.isStaticPreview || reduceTransparency {
            content.background(Color.white.opacity(reduceTransparency ? 1 : 0.48),in:RoundedRectangle(cornerRadius:radius,style:.continuous))
                .overlay(RoundedRectangle(cornerRadius:radius,style:.continuous).strokeBorder(.white.opacity(0.8),lineWidth:1).allowsHitTesting(false))
        } else if #available(macOS 26.0, *) {
            content
                .background(.white.opacity(0.18),in:RoundedRectangle(cornerRadius:radius,style:.continuous))
                .glassEffect(.regular.tint(orange.opacity(0.075)),in:RoundedRectangle(cornerRadius:radius,style:.continuous))
        } else {
            content.background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:radius,style:.continuous))
                .overlay(RoundedRectangle(cornerRadius:radius,style:.continuous).strokeBorder(.white.opacity(0.65),lineWidth:1).allowsHitTesting(false))
        }
    }
}
extension View {
    func clementineGlass(radius: CGFloat = 18) -> some View { modifier(ClementineGlassModifier(radius:radius)) }
}

/// Separate the visible presentation from the drop-target view so target geometry
/// never moves while the wheel springs into place.
@MainActor enum WheelMotion {
    static let openingDuration: TimeInterval = 0.32
    static let closingDuration: TimeInterval = 0.15
    static func present(_ layer: CALayer, shown: Bool, reduceMotion: Bool) {
        let current = layer.presentation() ?? layer
        let opacity = current.opacity
        let scale = (current.value(forKeyPath:"transform.scale") as? NSNumber)?.doubleValue ?? 1
        layer.removeAnimation(forKey:"wheel-opacity")
        layer.removeAnimation(forKey:"wheel-scale")
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.opacity = shown ? 1 : 0
        layer.transform = CATransform3DMakeScale(shown || reduceMotion ? 1 : 0.92, shown || reduceMotion ? 1 : 0.92, 1)
        CATransaction.commit()
        guard !reduceMotion else { return }
        let fade = CABasicAnimation(keyPath:"opacity")
        fade.fromValue = opacity; fade.toValue = shown ? 1 : 0
        fade.duration = shown ? 0.16 : closingDuration
        fade.timingFunction = CAMediaTimingFunction(name:shown ? .easeOut : .easeIn)
        layer.add(fade,forKey:"wheel-opacity")
        if shown {
            let spring = CASpringAnimation(keyPath:"transform.scale")
            spring.mass = 1; spring.stiffness = 440; spring.damping = 29
            spring.fromValue = scale; spring.toValue = 1; spring.duration = openingDuration
            layer.add(spring,forKey:"wheel-scale")
        } else {
            let shrink = CABasicAnimation(keyPath:"transform.scale")
            shrink.fromValue = scale; shrink.toValue = 0.92; shrink.duration = closingDuration
            shrink.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
            layer.add(shrink,forKey:"wheel-scale")
        }
    }
}
