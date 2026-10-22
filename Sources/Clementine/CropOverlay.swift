import AppKit
import SwiftUI

enum CropHandle:CaseIterable {
    case topLeft,top,topRight,right,bottomRight,bottom,bottomLeft,left,move
    var left:Bool { [.topLeft,.left,.bottomLeft].contains(self) }
    var right:Bool { [.topRight,.right,.bottomRight].contains(self) }
    var top:Bool { [.topLeft,.top,.topRight].contains(self) }
    var bottom:Bool { [.bottomLeft,.bottom,.bottomRight].contains(self) }
}
enum CropGeometry {
    static func clamped(_ r:CGRect,minimum:CGSize = CGSize(width:0.001,height:0.001)) -> CGRect {
        let width = min(1,max(minimum.width,r.width.isFinite ? r.width : 1))
        let height = min(1,max(minimum.height,r.height.isFinite ? r.height : 1))
        return CGRect(x:min(1-width,max(0,r.minX.isFinite ? r.minX : 0)),y:min(1-height,max(0,r.minY.isFinite ? r.minY : 0)),width:width,height:height)
    }
    static func dragged(_ r:CGRect,handle:CropHandle,translation:CGSize,minimum:CGSize) -> CGRect {
        let r = clamped(r,minimum:minimum)
        if handle == .move { return clamped(r.offsetBy(dx:translation.width,dy:translation.height),minimum:minimum) }
        var x1 = r.minX,y1 = r.minY,x2 = r.maxX,y2 = r.maxY
        if handle.left { x1 = max(0,min(x2-minimum.width,x1+translation.width)) }
        if handle.right { x2 = min(1,max(x1+minimum.width,x2+translation.width)) }
        if handle.top { y1 = max(0,min(y2-minimum.height,y1+translation.height)) }
        if handle.bottom { y2 = min(1,max(y1+minimum.height,y2+translation.height)) }
        return CGRect(x:x1,y:y1,width:x2-x1,height:y2-y1)
    }
    static func pixelRect(options o:OperationOptions,size:CGSize) -> CGRect {
        let w = max(1,Int(size.width)),h = max(1,Int(size.height))
        let x = min(w-1,max(0,o.cropX)),y = min(h-1,max(0,o.cropY))
        return CGRect(x:x,y:y,width:min(w-x,max(1,o.width > 0 ? o.width : w-x)),height:min(h-y,max(1,o.height > 0 ? o.height : h-y)))
    }
    static func normalized(options:OperationOptions,size:CGSize) -> CGRect {
        let r = pixelRect(options:options,size:size)
        return CGRect(x:r.minX/max(1,size.width),y:r.minY/max(1,size.height),width:r.width/max(1,size.width),height:r.height/max(1,size.height))
    }
}

struct CropOverlay:NSViewRepresentable {
    var selection:CGRect;var pixelSize:CGSize;var changed:(CGRect)->Void
    func makeNSView(context:Context) -> CropSelectionView { CropSelectionView() }
    func updateNSView(_ view:CropSelectionView,context:Context) {
        view.selection = selection;view.pixelSize = pixelSize;view.changed = changed
        view.needsDisplay = true;view.window?.invalidateCursorRects(for:view)
    }
}
/// Native hit testing keeps the borders draggable even at the exact canvas edge.
final class CropSelectionView:NSView {
    var selection = CGRect(x:0,y:0,width:1,height:1)
    var pixelSize = CGSize(width:1,height:1)
    var changed:((CGRect)->Void)?
    private var anchor = CGPoint.zero,start = CGRect.zero,handle:CropHandle?
    override var isFlipped:Bool { true }
    override var acceptsFirstResponder:Bool { true }
    var rectangle:CGRect { CGRect(x:selection.minX*bounds.width,y:selection.minY*bounds.height,width:selection.width*bounds.width,height:selection.height*bounds.height) }
    func point(_ handle:CropHandle) -> CGPoint {
        let r = rectangle
        return CGPoint(x:handle.left ? r.minX : (handle.right ? r.maxX : r.midX),y:handle.top ? r.minY : (handle.bottom ? r.maxY : r.midY))
    }
    func handle(at point:CGPoint) -> CropHandle? {
        for handle in CropHandle.allCases where handle != .move {
            let p = self.point(handle)
            if abs(point.x-p.x) <= 12 && abs(point.y-p.y) <= 12 { return handle }
        }
        let r = rectangle
        if point.y >= r.minY && point.y <= r.maxY {
            if abs(point.x-r.minX) <= 8 { return .left };if abs(point.x-r.maxX) <= 8 { return .right }
        }
        if point.x >= r.minX && point.x <= r.maxX {
            if abs(point.y-r.minY) <= 8 { return .top };if abs(point.y-r.maxY) <= 8 { return .bottom }
        }
        return r.contains(point) ? .move : nil
    }
    override func draw(_ dirtyRect:NSRect) {
        let r = rectangle
        let shade = NSBezierPath(rect:bounds);shade.appendRect(r);shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.5).setFill();shade.fill()
        let border = NSBezierPath(rect:r.insetBy(dx:1,dy:1));border.lineWidth = 2
        NSColor.white.setStroke();border.stroke()
        let grid = NSBezierPath();grid.lineWidth = 0.7
        for n in 1...2 {
            let f = CGFloat(n)/3;grid.move(to:CGPoint(x:r.minX+r.width*f,y:r.minY));grid.line(to:CGPoint(x:r.minX+r.width*f,y:r.maxY))
            grid.move(to:CGPoint(x:r.minX,y:r.minY+r.height*f));grid.line(to:CGPoint(x:r.maxX,y:r.minY+r.height*f))
        }
        NSColor.white.withAlphaComponent(0.55).setStroke();grid.stroke()
        for handle in CropHandle.allCases where handle != .move {
            let p = point(handle)
            let box = CGRect(x:min(bounds.maxX-10,max(0,p.x-5)),y:min(bounds.maxY-10,max(0,p.y-5)),width:10,height:10)
            let path = NSBezierPath(roundedRect:box,xRadius:2,yRadius:2)
            NSColor.white.setFill();path.fill();NSColor(red:0.97,green:0.36,blue:0.08,alpha:1).setStroke();path.lineWidth = 1.5;path.stroke()
        }
    }
    override func resetCursorRects() {
        addCursorRect(bounds,cursor:.crosshair);addCursorRect(rectangle.intersection(bounds),cursor:.openHand)
        let r = rectangle
        for x in [r.minX,r.maxX] { addCursorRect(CGRect(x:x-8,y:r.minY,width:16,height:r.height).intersection(bounds),cursor:.resizeLeftRight) }
        for y in [r.minY,r.maxY] { addCursorRect(CGRect(x:r.minX,y:y-8,width:r.width,height:16).intersection(bounds),cursor:.resizeUpDown) }
        for handle in CropHandle.allCases where handle != .move {
            let p = point(handle)
            let cursor:NSCursor = [.left,.right].contains(handle) ? .resizeLeftRight : ([.top,.bottom].contains(handle) ? .resizeUpDown : .crosshair)
            addCursorRect(CGRect(x:p.x-12,y:p.y-12,width:24,height:24).intersection(bounds),cursor:cursor)
        }
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self);anchor = convert(event.locationInWindow,from:nil);start = selection;handle = handle(at:anchor)
        if handle == .move { NSCursor.closedHand.set() }
    }
    override func mouseDragged(with event:NSEvent) {
        guard bounds.width > 0,bounds.height > 0 else { return }
        let location = convert(event.locationInWindow,from:nil)
        let minimum = CGSize(width:1/max(1,pixelSize.width),height:1/max(1,pixelSize.height))
        if let handle {
            selection = CropGeometry.dragged(start,handle:handle,translation:CGSize(width:(location.x-anchor.x)/bounds.width,height:(location.y-anchor.y)/bounds.height),minimum:minimum)
        } else {
            let x1 = min(1,max(0,anchor.x/bounds.width)),y1 = min(1,max(0,anchor.y/bounds.height))
            let x2 = min(1,max(0,location.x/bounds.width)),y2 = min(1,max(0,location.y/bounds.height))
            selection = CropGeometry.clamped(CGRect(x:min(x1,x2),y:min(y1,y2),width:abs(x2-x1),height:abs(y2-y1)),minimum:minimum)
        }
        needsDisplay = true;changed?(selection)
    }
    override func mouseUp(with event:NSEvent) { handle = nil;window?.invalidateCursorRects(for:self) }
    override func keyDown(with event:NSEvent) {
        let amount:CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        let dx:CGFloat = event.keyCode == 123 ? -amount : (event.keyCode == 124 ? amount : 0)
        let dy:CGFloat = event.keyCode == 126 ? -amount : (event.keyCode == 125 ? amount : 0)
        if dx == 0 && dy == 0 { super.keyDown(with:event);return }
        let handle:CropHandle = event.modifierFlags.contains(.option) ? .bottomRight : .move
        selection = CropGeometry.dragged(selection,handle:handle,translation:CGSize(width:dx/max(1,pixelSize.width),height:dy/max(1,pixelSize.height)),minimum:CGSize(width:1/max(1,pixelSize.width),height:1/max(1,pixelSize.height)))
        changed?(selection);needsDisplay = true
    }
}
