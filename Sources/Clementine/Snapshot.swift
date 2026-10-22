import AppKit
import SwiftUI

@MainActor enum Snapshot {
    static func render(path:String) throws {
        let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
        let controller = AppController.shared
        let args = Array(CommandLine.arguments.dropFirst(3))
        var size = NSSize(width:1000,height:740)
        let view:NSView
        if args.first == "--editor",args.count >= 3,let tool = Tool(rawValue:args[1]) {
            let files = FileSelection(urls:args.dropFirst(2).map { URL(fileURLWithPath:$0) })
            let model = EditorModel(operation:tool.descriptor,files:files)
            if [.redactImage,.annotateImage].contains(tool) { model.options.rectangles = [CGRect(x:0.15,y:0.18,width:0.45,height:0.3)]; model.options.annotation = "Clementine" }
            view = NSHostingView(rootView:EditorView(model:model,export:{ _ in })); size = NSSize(width:1080,height:760)
        } else if args.first == "--wheel",args.count >= 2 {
            let wheel = WheelController(app:controller); controller.wheel = wheel
            wheel.selection = FileSelection(urls:args.dropFirst().map { URL(fileURLWithPath:$0) }); wheel.options = Registry.operations(.convert,wheel.selection); wheel.selected = 1
            view = wheel.view; size = NSSize(width:410,height:410)
        } else {
            if args.first == "--settings" { controller.showSettings = true }
            else if !args.isEmpty { controller.selection = FileSelection(urls:args.map { URL(fileURLWithPath:$0) }) }
            view = NSHostingView(rootView:HomeView(app:controller))
        }
        let w = NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.borderless],backing:.buffered,defer:false)
        view.frame = NSRect(origin:.zero,size:size); w.contentView = view; view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until:Date().addingTimeInterval(0.7))
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { throw ClementineError.message("Could not render the UI.") }
        view.cacheDisplay(in:view.bounds,to:bitmap)
        guard let data = bitmap.representation(using:.png,properties:[:]) else { throw ClementineError.message("Could not encode the UI preview.") }
        try data.write(to:URL(fileURLWithPath:path))
    }
}
