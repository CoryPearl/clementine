import AppKit
let root = URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let image = NSImage(size:NSSize(width:size,height:size))
    image.lockFocus()
    let s = CGFloat(size)/1024
    let ctx = NSGraphicsContext.current!.cgContext; ctx.scaleBy(x:s,y:s)
    let rect = NSRect(x:32,y:32,width:960,height:960)
    NSColor(calibratedRed:0.98,green:0.95,blue:0.88,alpha:1).setFill(); NSBezierPath(roundedRect:rect,xRadius:210,yRadius:210).fill()
    NSColor(calibratedRed:0.93,green:0.37,blue:0.12,alpha:1).setFill(); NSBezierPath(ovalIn:NSRect(x:177,y:150,width:670,height:670)).fill()
    NSColor(calibratedRed:1,green:0.60,blue:0.22,alpha:1).setFill(); NSBezierPath(ovalIn:NSRect(x:216,y:187,width:592,height:592)).fill()
    for i in 0..<7 {
        let angle = CGFloat(i)*2 * .pi/7; let gap:CGFloat = 0.045
        let c = NSPoint(x:512,y:483); let p = NSBezierPath()
        p.move(to:NSPoint(x:c.x+70*cos(angle+gap),y:c.y+70*sin(angle+gap)))
        p.line(to:NSPoint(x:c.x+267*cos(angle+gap),y:c.y+267*sin(angle+gap)))
        p.appendArc(withCenter:c,radius:267,startAngle:(angle+gap)*180 / .pi,endAngle:(angle+2 * .pi/7-gap)*180 / .pi)
        p.line(to:NSPoint(x:c.x+70*cos(angle+2 * .pi/7-gap),y:c.y+70*sin(angle+2 * .pi/7-gap))); p.close()
        NSColor(calibratedRed:1,green:0.80,blue:0.43,alpha:1).setFill(); p.fill()
    }
    let leaf = NSBezierPath(); leaf.move(to:NSPoint(x:510,y:779)); leaf.curve(to:NSPoint(x:725,y:911),controlPoint1:NSPoint(x:503,y:927),controlPoint2:NSPoint(x:654,y:949)); leaf.curve(to:NSPoint(x:510,y:779),controlPoint1:NSPoint(x:721,y:800),controlPoint2:NSPoint(x:599,y:763)); NSColor(calibratedRed:0.20,green:0.36,blue:0.23,alpha:1).setFill(); leaf.fill()
    image.unlockFocus()
    let rep = NSBitmapImageRep(data:image.tiffRepresentation!)!
    let data = rep.representation(using:.png,properties:[:])!
    let names:[String]
    switch size { case 16:names=["icon_16x16.png"];case 32:names=["icon_16x16@2x.png","icon_32x32.png"];case 64:names=["icon_32x32@2x.png"];case 128:names=["icon_128x128.png"];case 256:names=["icon_128x128@2x.png","icon_256x256.png"];case 512:names=["icon_256x256@2x.png","icon_512x512.png"];default:names=["icon_512x512@2x.png"] }
    for name in names { try data.write(to:root.appendingPathComponent(name)) }
}
