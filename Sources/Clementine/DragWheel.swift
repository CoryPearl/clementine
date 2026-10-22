import AppKit
import SwiftUI
import QuartzCore

@MainActor final class DragMonitor {
    unowned let app:AppController
    var monitors:[Any] = []; var dragging = false; var baseline = 0; var suppressed = false
    init(app:AppController) { self.app = app }
    func start() {
        let mask:NSEvent.EventTypeMask = [.leftMouseDown,.leftMouseDragged,.leftMouseUp,.flagsChanged,.keyDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching:mask,handler:{ [weak self] e in self?.handle(e) }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching:mask,handler:{ [weak self] e in self?.handle(e); return e }) { monitors.append(m) }
    }
    func handle(_ e:NSEvent) {
        if e.type == .leftMouseDown { dragging = false; suppressed = false; baseline = NSPasteboard(name:.drag).changeCount }
        if e.type == .leftMouseDragged { dragging = true }
        if e.type == .leftMouseUp {
            dragging = false
            let presentation = app.wheel.presentationID
            DispatchQueue.main.asyncAfter(deadline:.now()+0.04) { [weak self] in self?.app.wheel.hide(expectedPresentation:presentation) }
            return
        }
        if e.type == .keyDown && app.wheel.visible {
            if e.keyCode == 53 { suppressed = true; app.wheel.hide(); return }
            if e.keyCode == 124 || e.keyCode == 125 { app.wheel.step(1) }; if e.keyCode == 123 || e.keyCode == 126 { app.wheel.step(-1) }
            if e.keyCode == 36 { suppressed = true; app.wheel.apply() }; return
        }
        guard !suppressed,(dragging || NSEvent.pressedMouseButtons & 1 != 0) else { return }
        guard e.type == .flagsChanged || (e.type == .leftMouseDragged && !app.wheel.visible) else { return }
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mode:WheelMode?
        for (m,key,defaultKey) in [(WheelMode.convert,"convertKey","Shift"),(.tools,"toolsKey","Command"),(.actions,"actionsKey","Control")] {
            let name = UserDefaults.standard.string(forKey:key) ?? defaultKey
            let flag:NSEvent.ModifierFlags = ["Shift":.shift,"Command":.command,"Control":.control,"Option":.option][name] ?? .shift
            if f.contains(flag) { mode = m; break }
        }
        guard let mode else { return }
        if app.wheel.visible { app.wheel.changeMode(mode); return }
        let board = NSPasteboard(name:.drag)
        guard board.changeCount != baseline, let urls = board.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL],!urls.isEmpty else { return }
        app.wheel.show(urls:urls,mode:mode,point:NSEvent.mouseLocation)
    }
}
@MainActor final class WheelController {
    unowned let app: AppController
    var panel: NSPanel!
    var view: WheelView!
    var selection = FileSelection(urls:[])
    var mode: WheelMode = .convert
    var options: [OperationDescriptor] = []
    var page = 0
    var selected: Int? {
        didSet { if selected != oldValue { view?.selectionChanged() } }
    }
    private(set) var visible = false
    private(set) var presentationID: UInt = 0
    private var pendingClose: DispatchWorkItem?
    let perPage = 8
    let reduceMotion: () -> Bool
    init(app: AppController, reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.app = app; self.reduceMotion = reduceMotion
        panel = NSPanel(contentRect:NSRect(x:0,y:0,width:410,height:410),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.level = .popUpMenu
        panel.appearance = NSAppearance(named:.aqua)
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.transient]; panel.hidesOnDeactivate = false
        view = WheelView(controller:self); panel.contentView = view
    }
    var displayed: [OperationDescriptor] { Array(options.dropFirst(page*perPage).prefix(perPage)) }
    func show(urls:[URL], mode:WheelMode, point:NSPoint) {
        selection = FileSelection(urls:urls); self.mode = mode; page = 0; selected = nil
        options = Registry.operations(mode,selection)
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main!
        let frame = screen.visibleFrame
        let x = min(max(point.x-205,frame.minX),frame.maxX-410), y = min(max(point.y-205,frame.minY),frame.maxY-410)
        panel.setFrameOrigin(NSPoint(x:x,y:y))
        present()
    }
    func present() {
        pendingClose?.cancel(); pendingClose = nil
        presentationID &+= 1; visible = true; panel.ignoresMouseEvents = false
        view.updateContents()
        if !panel.isVisible {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            view.animationHost.layer?.opacity = 0
            view.animationHost.layer?.transform = CATransform3DMakeScale(0.84,0.84,1)
            CATransaction.commit()
        }
        if let layer = view.animationHost.layer { WheelMotion.present(layer,shown:true,reduceMotion:reduceMotion()) }
        panel.orderFrontRegardless()
    }
    func changeMode(_ mode:WheelMode) {
        guard self.mode != mode else { return }
        view.beginContentTransition()
        self.mode = mode; options = Registry.operations(mode,selection); page = 0; selected = nil
        view.updateContents()
    }
    func hide(expectedPresentation:UInt? = nil) {
        guard visible, expectedPresentation == nil || expectedPresentation == presentationID else { return }
        visible = false; panel.ignoresMouseEvents = true
        let id = presentationID
        if let layer = view.animationHost.layer { WheelMotion.present(layer,shown:false,reduceMotion:reduceMotion()) }
        let close = DispatchWorkItem { [weak self] in
            guard let self, !self.visible, self.presentationID == id else { return }
            self.panel.orderOut(nil); self.selected = nil; self.view.stopHighlightAnimation()
            self.pendingClose = nil
        }
        pendingClose?.cancel(); pendingClose = close
        if reduceMotion() { close.perform() }
        else { DispatchQueue.main.asyncAfter(deadline:.now()+WheelMotion.closingDuration,execute:close) }
    }
    func step(_ delta:Int) {
        guard !displayed.isEmpty else { return }
        selected = ((selected ?? -1)+delta+displayed.count)%displayed.count
    }
    func changePage(_ delta:Int) {
        view.beginContentTransition()
        let count = max(1,Int(ceil(Double(options.count)/Double(perPage))))
        page = (page+delta+count)%count; selected = nil; view.updateContents()
    }
    func apply() {
        guard visible, let selected, displayed.indices.contains(selected) else { hide(); return }
        let operation = displayed[selected], files = selection
        hide()
        DispatchQueue.main.async { self.app.invoke(operation,selection:files) }
    }
}

/// The same rounded paths mask the real glass and define the accepted drop area.
enum WheelGeometry {
    static let center = CGPoint(x:205,y:205)
    static func segment(_ index:Int, count:Int) -> CGPath {
        let path = CGMutablePath()
        guard count > 0 else { return path }
        let half = CGFloat.pi/CGFloat(count)
        let middle = CGFloat.pi/2-CGFloat(index)*2*half
        let start = middle+half-0.018, end = middle-half+0.018
        let inner:CGFloat = 60, outer:CGFloat = 166, corner:CGFloat = min(12,(outer*(start-end))/5)
        let outerInset = corner/outer, innerInset = min(corner/inner,(start-end)/4)
        func p(_ r:CGFloat,_ a:CGFloat) -> CGPoint { CGPoint(x:center.x+r*cos(a),y:center.y+r*sin(a)) }
        path.move(to:p(inner+corner,start)); path.addLine(to:p(outer-corner,start))
        path.addQuadCurve(to:p(outer,start-outerInset),control:p(outer,start))
        path.addArc(center:center,radius:outer,startAngle:start-outerInset,endAngle:end+outerInset,clockwise:true)
        path.addQuadCurve(to:p(outer-corner,end),control:p(outer,end))
        path.addLine(to:p(inner+corner,end))
        path.addQuadCurve(to:p(inner,end+innerInset),control:p(inner,end))
        path.addArc(center:center,radius:inner,startAngle:end+innerInset,endAngle:start-innerInset,clockwise:false)
        path.addQuadCurve(to:p(inner+corner,start),control:p(inner,start)); path.closeSubpath()
        return path
    }
    static let hub = CGPath(ellipseIn:CGRect(x:157,y:157,width:96,height:96),transform:nil)
}

@MainActor final class WheelView: NSView {
    unowned let controller: WheelController
    let animationHost = NSView(frame:NSRect(x:0,y:0,width:410,height:410))
    private let glassHost = NSView(frame:NSRect(x:0,y:0,width:410,height:410))
    private var artwork: WheelArtworkView!
    private var glassSurfaces: [NSView] = []
    private var layoutIDs: [String] = []
    private var tracking: NSTrackingArea?
    private var highlightTimer: Timer?
    private var highlightStart = CACurrentMediaTime()
    private var highlightFrom: [CGFloat] = []
    private(set) var highlights: [CGFloat] = []
    init(controller:WheelController) {
        self.controller = controller
        super.init(frame:NSRect(x:0,y:0,width:410,height:410))
        wantsLayer = true; animationHost.wantsLayer = true
        addSubview(animationHost); animationHost.addSubview(glassHost)
        animationHost.layer?.anchorPoint = CGPoint(x:0.5,y:0.5)
        animationHost.layer?.position = CGPoint(x:205,y:205)
        artwork = WheelArtworkView(wheel:self); animationHost.addSubview(artwork)
        registerForDraggedTypes([.fileURL,NSPasteboard.PasteboardType("NSFilenamesPboardType")])
    }
    required init?(coder:NSCoder) { fatalError() }
    deinit { highlightTimer?.invalidate() }
    override var acceptsFirstResponder: Bool { true }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:bounds,options:[.mouseMoved,.activeAlways],owner:self)
        addTrackingArea(tracking!); super.updateTrackingAreas()
    }
    func updateContents() {
        let ids = controller.displayed.map(\.id)
        if ids != layoutIDs || glassSurfaces.isEmpty {
            stopHighlightAnimation(); layoutIDs = ids
            highlights = ids.indices.map { controller.selected == $0 ? 1 : 0 }; highlightFrom = highlights
            glassSurfaces.forEach { $0.removeFromSuperview() }; glassSurfaces = []
            for index in 0..<ids.count { addGlass(path:WheelGeometry.segment(index,count:ids.count),tint:accent.withAlphaComponent(0.15)) }
            addGlass(path:WheelGeometry.hub,tint:accent.withAlphaComponent(0.8))
        }
        artwork.needsDisplay = true
    }
    private func addGlass(path:CGPath,tint:NSColor) {
        let glass = GlassStyle.surface(frame:bounds,tint:tint,radius:18)
        let mask = CAShapeLayer(); mask.frame = bounds; mask.path = path
        glass.layer?.mask = mask
        glassHost.addSubview(glass); glassSurfaces.append(glass)
    }
    func beginContentTransition() {
        guard !controller.reduceMotion() else { return }
        let transition = CATransition(); transition.type = .fade; transition.duration = 0.16
        transition.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
        animationHost.layer?.add(transition,forKey:"wheel-content")
    }
    func selectionChanged() {
        guard highlights.count == controller.displayed.count else { updateContents(); return }
        highlightFrom = highlights; highlightStart = CACurrentMediaTime()
        stopHighlightAnimation()
        if controller.reduceMotion() {
            highlights = highlights.indices.map { controller.selected == $0 ? 1 : 0 }
            artwork.needsDisplay = true; return
        }
        highlightTimer = Timer(timeInterval:1.0/60,repeats:true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickHighlights() }
        }
        RunLoop.main.add(highlightTimer!,forMode:.common)
    }
    private func tickHighlights() {
        let t = min(1,(CACurrentMediaTime()-highlightStart)/0.15)
        let eased = CGFloat(t*t*(3-2*t))
        highlights = highlightFrom.enumerated().map { index,from in from+((controller.selected == index ? 1 : 0)-from)*eased }
        artwork.needsDisplay = true
        if t >= 1 { stopHighlightAnimation() }
    }
    func stopHighlightAnimation() { highlightTimer?.invalidate(); highlightTimer = nil }
    func index(_ point:NSPoint) -> Int? {
        controller.displayed.indices.first { WheelGeometry.segment($0,count:controller.displayed.count).contains(point) }
    }
    override func hitTest(_ point:NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func mouseMoved(with event:NSEvent) { highlight(convert(event.locationInWindow,from:nil)) }
    func highlight(_ point:NSPoint) {
        let next = index(point)
        if next != controller.selected {
            controller.selected = next
            if next != nil,UserDefaults.standard.bool(forKey:"sound") { NSSound(named:"Tink")?.play() }
        }
    }
    override func mouseDown(with event:NSEvent) {
        let point = convert(event.locationInWindow,from:nil)
        if hypot(point.x-205,point.y-205) < 50 { controller.changePage(1) }
        else { highlight(point); controller.apply() }
    }
    override func scrollWheel(with event:NSEvent) { if abs(event.scrollingDeltaY) > 1 { controller.changePage(event.scrollingDeltaY > 0 ? 1 : -1) } }
    override func keyDown(with event:NSEvent) {
        if event.keyCode == 53 { controller.hide() }
        else if event.keyCode == 36 { controller.apply() }
        else if event.keyCode == 48 { controller.changePage(1) }
        else { controller.step(event.keyCode == 123 || event.keyCode == 126 ? -1 : 1) }
    }
    override func draggingEntered(_ sender:NSDraggingInfo) -> NSDragOperation {
        guard controller.visible else { return [] }
        if let urls = sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL],!urls.isEmpty {
            controller.selection = FileSelection(urls:urls)
            controller.options = Registry.operations(controller.mode,controller.selection)
            updateContents()
        }
        highlight(convert(sender.draggingLocation,from:nil)); return .copy
    }
    override func draggingUpdated(_ sender:NSDraggingInfo) -> NSDragOperation {
        guard controller.visible else { return [] }
        highlight(convert(sender.draggingLocation,from:nil)); return controller.selected == nil ? [] : .copy
    }
    override func draggingExited(_ sender:NSDraggingInfo?) { controller.selected = nil }
    override func prepareForDragOperation(_ sender:NSDraggingInfo) -> Bool {
        guard controller.visible else { return false }
        highlight(convert(sender.draggingLocation,from:nil)); return controller.selected != nil
    }
    override func performDragOperation(_ sender:NSDraggingInfo) -> Bool {
        guard controller.visible else { return false }
        highlight(convert(sender.draggingLocation,from:nil))
        guard controller.selected != nil else { return false }; controller.apply(); return true
    }
    fileprivate func drawArtwork() {
        let options = controller.displayed
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byWordWrapping
        for (index,item) in options.enumerated() {
            let path = WheelGeometry.segment(index,count:options.count)
            let strength = highlights.indices.contains(index) ? highlights[index] : (controller.selected == index ? 1 : 0)
            context.saveGState()
            context.setShadow(offset:CGSize(width:0,height:-4),blur:12,color:NSColor.brown.withAlphaComponent(0.13).cgColor)
            context.setFillColor(NSColor(calibratedRed:1,green:0.78,blue:0.48,alpha:opaque ? 1 : 0.12).cgColor)
            context.addPath(path); context.fillPath(); context.restoreGState()
            context.saveGState(); context.addPath(path); context.clip()
            let light = NSColor(calibratedRed:1,green:0.94,blue:0.84,alpha:opaque ? 1 : 0.42)
            let warm = NSColor(calibratedRed:1,green:0.57,blue:0.20,alpha:opaque ? 1 : 0.18)
            if let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[light.cgColor,warm.cgColor] as CFArray,locations:[0,1]) {
                context.drawLinearGradient(gradient,start:CGPoint(x:50,y:370),end:CGPoint(x:360,y:20),options:[])
            }
            if strength > 0,let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[NSColor(calibratedRed:1,green:0.63,blue:0.25,alpha:strength*0.97).cgColor,NSColor(calibratedRed:0.97,green:0.29,blue:0.035,alpha:strength*0.94).cgColor] as CFArray,locations:[0,1]) {
                context.drawLinearGradient(gradient,start:CGPoint(x:80,y:350),end:CGPoint(x:330,y:50),options:[])
            }
            context.restoreGState()
            context.addPath(path); context.setStrokeColor(NSColor.white.withAlphaComponent(0.7+strength*0.25).cgColor); context.setLineWidth(1); context.strokePath()
            let angle = Double.pi/2-Double(index)*2*Double.pi/Double(options.count)
            let point = CGPoint(x:205+112*cos(angle),y:205+112*sin(angle))
            let normal = NSColor(calibratedRed:0.43,green:0.20,blue:0.075,alpha:1)
            let color = normal.blended(withFraction:strength,of:.white) ?? normal
            if let icon = NSImage(systemSymbolName:item.symbol,accessibilityDescription:item.title)?.withSymbolConfiguration(.init(pointSize:21,weight:.medium)) {
                let tinted = icon.copy() as! NSImage
                tinted.lockFocus(); color.set(); NSRect(origin:.zero,size:tinted.size).fill(using:.sourceIn); tinted.unlockFocus()
                tinted.draw(in:NSRect(x:point.x-12,y:point.y+1,width:24,height:24))
            }
            item.title.draw(in:NSRect(x:point.x-45,y:point.y-30,width:90,height:26),withAttributes:[.font:NSFont.systemFont(ofSize:9,weight:.semibold),.foregroundColor:color,.paragraphStyle:paragraph])
        }
        context.saveGState(); context.addPath(WheelGeometry.hub); context.clip()
        if let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[NSColor(calibratedRed:1,green:0.65,blue:0.25,alpha:0.92).cgColor,NSColor(calibratedRed:0.92,green:0.26,blue:0.04,alpha:0.96).cgColor] as CFArray,locations:[0,1]) {
            context.drawLinearGradient(gradient,start:CGPoint(x:175,y:252),end:CGPoint(x:230,y:157),options:[])
        }
        context.restoreGState()
        context.addPath(WheelGeometry.hub); context.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor); context.setLineWidth(1.1); context.strokePath()
        controller.mode.rawValue.uppercased().draw(in:NSRect(x:159,y:201,width:92,height:14),withAttributes:[.font:NSFont.systemFont(ofSize:10,weight:.bold),.foregroundColor:NSColor.white,.paragraphStyle:paragraph])
        let label = options.isEmpty ? "No options" : controller.options.count > controller.perPage ? "\(controller.page+1)/\(Int(ceil(Double(controller.options.count)/8))) · scroll" : "Drop to apply"
        label.draw(in:NSRect(x:159,y:181,width:92,height:14),withAttributes:[.font:NSFont.systemFont(ofSize:9),.foregroundColor:NSColor.white.withAlphaComponent(0.88),.paragraphStyle:paragraph])
        if options.isEmpty { "Try Control for file actions".draw(in:NSRect(x:100,y:120,width:210,height:20),withAttributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.secondaryLabelColor,.paragraphStyle:paragraph]) }
    }
}
@MainActor private final class WheelArtworkView: NSView {
    unowned let wheel: WheelView
    init(wheel:WheelView) { self.wheel = wheel; super.init(frame:wheel.bounds) }
    required init?(coder:NSCoder) { fatalError() }
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect:NSRect) { wheel.drawArtwork() }
}
