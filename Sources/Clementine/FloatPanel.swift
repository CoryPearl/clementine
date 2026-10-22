import SwiftUI
import AppKit
import Quartz

@MainActor final class FloatModel:ObservableObject {
    @Published var urls:[URL]; @Published var selected:URL?; @Published var collapsed = false
    init(urls:[URL]) { self.urls = urls; self.selected = urls.first }
}
@MainActor final class FloatController:NSObject,NSWindowDelegate,@preconcurrency QLPreviewPanelDataSource {
    let model:FloatModel; let panel:NSPanel
    var snapping = false
    init(urls:[URL]) {
        model = FloatModel(urls:urls)
        panel = NSPanel(contentRect:NSRect(x:0,y:0,width:300,height:330),styleMask:[.titled,.closable,.resizable,.utilityWindow,.nonactivatingPanel],backing:.buffered,defer:false)
        super.init()
        panel.title = "Float · Clementine"; panel.isOpaque = false; panel.backgroundColor = .clear; panel.animationBehavior = .utilityWindow; panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; panel.delegate = self; panel.minSize = NSSize(width:180,height:100)
        panel.contentView = NSHostingView(rootView:FloatView(model:model,preview:{ [weak self] in self?.preview() }))
        panel.center()
    }
    func show() { panel.orderFrontRegardless() }
    func preview() { guard let ql = QLPreviewPanel.shared() else { return }; ql.dataSource = self; ql.reloadData(); ql.makeKeyAndOrderFront(nil) }
    func numberOfPreviewItems(in panel:QLPreviewPanel!)->Int { model.selected == nil ? 0 : 1 }
    func previewPanel(_ panel:QLPreviewPanel!,previewItemAt index:Int)->QLPreviewItem { model.selected! as NSURL }
    func windowWillClose(_ notification:Notification) { AppController.shared.floats.removeAll { $0 === self } }
    func windowDidMove(_ notification:Notification) {
        guard !snapping,let screen = panel.screen else { return }
        let f = panel.frame; let visible = screen.visibleFrame; var next = f.origin
        if abs(f.minX-visible.minX) < 20 { next.x = visible.minX }
        if abs(f.maxX-visible.maxX) < 20 { next.x = visible.maxX-f.width }
        if abs(f.maxY-visible.maxY) < 20 { next.y = visible.maxY-f.height }
        if abs(f.minY-visible.minY) < 20 { next.y = visible.minY }
        if next != f.origin { snapping = true; panel.setFrameOrigin(next); snapping = false }
    }
}
struct FloatView:View {
    @ObservedObject var model:FloatModel; var preview:()->Void
    var body:some View {
        VStack(spacing:0) {
            HStack { Text("\(model.urls.count) files at hand").font(.system(size:11,weight:.medium)); Spacer(); Button { model.collapsed.toggle() } label:{ Image(systemName:model.collapsed ? "chevron.down" : "chevron.up") }.buttonStyle(.plain) }.padding(12)
            if !model.collapsed {
                Divider()
                List(model.urls,id:\.self,selection:$model.selected) { url in
                    HStack(spacing:10) { Image(nsImage:NSWorkspace.shared.icon(forFile:url.path)).resizable().frame(width:32,height:32); VStack(alignment:.leading,spacing:3) { Text(url.lastPathComponent).font(.system(size:11,weight:.medium)).lineLimit(1); Text(url.deletingLastPathComponent().path).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) } }.padding(.vertical,4)
                        .onDrag { NSItemProvider(contentsOf:url) ?? NSItemProvider(object:url as NSURL) }
                        .contextMenu { Button("Quick Look") { model.selected = url; preview() }; Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }; Button("Open") { NSWorkspace.shared.open(url) }; Divider(); Button("Remove from Float") { model.urls.removeAll { $0 == url } } }
                        .onTapGesture(count:2) { model.selected = url; preview() }
                }.listStyle(.plain).scrollContentBackground(.hidden)
                HStack { Text("Drag files out, or drop more in.").font(.system(size:9)).foregroundStyle(.secondary); Spacer(); Button { preview() } label:{ Image(systemName:"eye") }.buttonStyle(.plain).help("Quick Look") }.padding(12)
            }
        }.background(OrangeGlassBackdrop()).onDrop(of:["public.file-url"],isTargeted:nil) { providers in
            for provider in providers { provider.loadItem(forTypeIdentifier:"public.file-url",options:nil) { item,_ in
                if let data = item as? Data,let url = URL(dataRepresentation:data,relativeTo:nil) { DispatchQueue.main.async { if !model.urls.contains(url) { model.urls.append(url) } } }
            } }; return true
        }.onExitCommand { }.onKeyPressCompat { preview() }
    }
}
extension View {
    @ViewBuilder func onKeyPressCompat(_ action:@escaping()->Void)->some View { self.background(SpaceKeyHandler(action:action).frame(width:0,height:0)) }
}
struct SpaceKeyHandler:NSViewRepresentable {
    let action:()->Void
    func makeNSView(context:Context)->NSView { let v = KeyView(); v.action = action; return v }
    func updateNSView(_ nsView:NSView,context:Context) {}
    class KeyView:NSView { var action:(()->Void)?; var monitor:Any?; override func viewDidMoveToWindow() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in if event.window == self?.window,event.keyCode == 49 { self?.action?(); return nil }; return event } }; deinit { if let monitor { NSEvent.removeMonitor(monitor) } } }
}
