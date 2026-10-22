import AppKit
import SwiftUI
import ApplicationServices
import ServiceManagement

@main struct ClementineMain {
    @MainActor static func main() {
        if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--snapshot" {
            do { try Snapshot.render(path:CommandLine.arguments[2]) } catch { fputs(error.localizedDescription+"\n",stderr); exit(1) }; return
        }
        if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "--convert" || CommandLine.arguments.dropFirst().first == "--tool" {
            CLI.run(); return
        }
        let app = NSApplication.shared
        let delegate = AppController.shared
        app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
    }
}
enum CLI {
    static func run() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count >= 3 else { fputs("Usage: Clementine --convert FORMAT FILE... [--output FOLDER]\n       Clementine --tool TOOL FILE... [--output FOLDER]\n",stderr); exit(2) }
        var options = OperationOptions(); var paths:[String] = []; var i = 2
        while i < args.count {
            if args[i] == "--output", i+1 < args.count { options.destination = URL(fileURLWithPath:args[i+1]); i += 2 }
            else { paths.append(args[i]); i += 1 }
        }
        do {
            let request = ConversionRequest(urls:paths.map { URL(fileURLWithPath:$0) },operation:(args[0] == "--convert" ? "convert:" : "tool:")+args[1],options:options)
            let results = try Engine(token:CancellationToken()).execute(request) { _,message in fputs(message+"\n",stderr) }
            for result in results { print(result.path) }
        } catch { fputs(error.localizedDescription+"\n",stderr); exit(1) }
    }
}
@MainActor final class AppController: NSObject,NSApplicationDelegate,NSWindowDelegate,ObservableObject {
    static let shared = AppController()
    @Published var selection = FileSelection(urls:[])
    @Published var mode:WheelMode = .convert
    @Published var jobs:[Job] = []
    @Published var showSettings = false
    @Published var errorText:String?
    @Published var engineReady = false
    var status:NSStatusItem!; var window:NSWindow?; var editors:[NSWindow] = []; var floats:[FloatController] = []
    var wheel:WheelController!; var monitor:DragMonitor!
    let queue = OperationQueue()
    func applicationDidFinishLaunching(_ notification:Notification) {
        queue.maxConcurrentOperationCount = 2
        let mainMenu = NSMenu()
        let appItem = NSMenuItem();let appMenu = NSMenu(title:"Clementine")
        appMenu.addItem(withTitle:"About Clementine",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"").target = NSApp
        appMenu.addItem(withTitle:"Settings…",action:#selector(settings),keyEquivalent:",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:"Quit Clementine",action:#selector(quit),keyEquivalent:"q").target = self
        appItem.submenu = appMenu;mainMenu.addItem(appItem)
        let editItem = NSMenuItem();let editMenu = NSMenu(title:"Edit")
        for (title,selector,key) in [("Undo","undo:","z"),("Cut","cut:","x"),("Copy","copy:","c"),("Paste","paste:","v"),("Select All","selectAll:","a")] {
            editMenu.addItem(withTitle:title,action:NSSelectorFromString(selector),keyEquivalent:key)
        }
        editItem.submenu = editMenu;mainMenu.addItem(editItem)
        let windowItem = NSMenuItem();let windowMenu = NSMenu(title:"Window")
        windowMenu.addItem(withTitle:"Close",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w")
        windowMenu.addItem(withTitle:"Minimize",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m")
        windowItem.submenu = windowMenu;mainMenu.addItem(windowItem);NSApp.mainMenu = mainMenu;NSApp.windowsMenu = windowMenu
        status = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        if let button = status.button {
            button.image = NSImage(systemSymbolName:"circle.hexagongrid.fill",accessibilityDescription:"Clementine")
            button.action = #selector(statusClick); button.target = self; button.sendAction(on:[.leftMouseUp,.rightMouseUp])
        }
        wheel = WheelController(app:self); monitor = DragMonitor(app:self); monitor.start()
        engineReady = FileManager.default.isExecutableFile(atPath:Engine.toolsRoot.appendingPathComponent("ffmpeg").path)
        if !UserDefaults.standard.bool(forKey:"hasOpened") { openWindow(); UserDefaults.standard.set(true,forKey:"hasOpened") }
        NotificationCenter.default.addObserver(self,selector:#selector(openWindow),name:NSNotification.Name("ClementineOpen"),object:nil)
    }
    @objc func statusClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu(); menu.addItem(withTitle:"Open Clementine",action:#selector(openWindow),keyEquivalent:"")
            menu.addItem(withTitle:"Settings…",action:#selector(settings),keyEquivalent:","); menu.addItem(.separator())
            menu.addItem(withTitle:"Quit Clementine",action:#selector(quit),keyEquivalent:"q")
            for item in menu.items { item.target = self }; status.menu = menu; status.button?.performClick(nil); status.menu = nil
        } else { openWindow() }
    }
    @objc func openWindow() {
        if window == nil {
            let w = NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:740),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
            w.title = "Clementine"; w.titlebarAppearsTransparent = true; w.isOpaque = false; w.backgroundColor = .clear; w.animationBehavior = .utilityWindow; w.isReleasedWhenClosed = false; w.minSize = NSSize(width:840,height:620)
            w.contentView = NSHostingView(rootView:HomeView(app:self)); w.center(); window = w
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    @objc func settings() { showSettings = true; openWindow() }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool { openWindow(); return true }
    func application(_ sender:NSApplication,openFiles filenames:[String]) { selection = FileSelection(urls:filenames.map { URL(fileURLWithPath:$0) }); openWindow(); sender.reply(toOpenOrPrint:.success) }
    func chooseFiles() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { selection = FileSelection(urls:panel.urls) }
    }
    func accept(_ urls:[URL]) { guard !urls.isEmpty else { return }; selection = FileSelection(urls:urls) }
    func invoke(_ operation:OperationDescriptor,selection:FileSelection? = nil) {
        let files = selection ?? self.selection
        guard !files.urls.isEmpty else { return }
        wheel.hide()
        if operation.id.hasPrefix("action:") { action(String(operation.id.dropFirst(7)),files); return }
        if operation.needsEditor { openEditor(operation,files); return }
        var options = OperationOptions()
        if let path = UserDefaults.standard.string(forKey:"outputFolder"),!path.isEmpty { options.destination = URL(fileURLWithPath:path) }
        let quality = UserDefaults.standard.double(forKey:"quality"); if quality > 0 { options.quality = quality }
        submit(.init(urls:files.urls,operation:operation.id,options:options),title:operation.title)
    }
    func openEditor(_ operation:OperationDescriptor,_ files:FileSelection) {
        let w = NSWindow(contentRect:NSRect(x:0,y:0,width:1080,height:760),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        w.title = "\(operation.title) — \(files.label)"; w.isOpaque = false; w.backgroundColor = .clear; w.animationBehavior = .utilityWindow; w.delegate = self; w.isReleasedWhenClosed = false; w.minSize = NSSize(width:900,height:650)
        let model = EditorModel(operation:operation,files:files)
        w.contentView = NSHostingView(rootView:EditorView(model:model) { [weak self,weak w] options in
            self?.submit(.init(urls:files.urls,operation:operation.id,options:options),title:operation.title); w?.close()
        }); w.center(); w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); editors.append(w)
    }
    func windowWillClose(_ notification:Notification) {
        if let closed = notification.object as? NSWindow { editors.removeAll { $0 === closed } }
    }
    func submit(_ request:ConversionRequest,title:String) {
        let job = Job(name:FileSelection(urls:request.urls).label,operation:title); jobs.insert(job,at:0)
        queue.addOperation { [weak self] in
            Task { @MainActor in job.state = .running; job.message = "Starting…" }
            do {
                let outputs = try Engine(token:job.token).execute(request) { progress,message in Task { @MainActor in job.progress = progress; job.message = message } }
                Task { @MainActor in job.outputs = outputs; job.state = .completed; job.message = "\(outputs.count) output\(outputs.count == 1 ? "" : "s") saved"; if UserDefaults.standard.bool(forKey:"sound") { NSSound(named:"Glass")?.play() } }
            } catch {
                Task { @MainActor in job.state = error is CancellationError ? .cancelled : .failed; job.message = error.localizedDescription; self?.openWindow() }
            }
        }
    }
    func action(_ action:String,_ files:FileSelection) {
        switch action {
        case "path": NSPasteboard.general.clearContents(); NSPasteboard.general.setString(files.urls.map(\.path).joined(separator:"\n"),forType:.string)
        case "copy": NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(files.urls as [NSURL])
        case "float": let controller = FloatController(urls:files.urls); floats.append(controller); controller.show()
        case "airdrop":
            guard let service = NSSharingService(named:.sendViaAirDrop),service.canPerform(withItems:files.urls) else { errorText = "AirDrop is unavailable for this selection."; openWindow(); return }
            service.perform(withItems:files.urls)
        case "move":
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Move Here"
            guard panel.runModal() == .OK,let destination = panel.url else { return }
            var moved:[(URL,URL)] = []
            do {
                let names = files.urls.map { $0.lastPathComponent.lowercased() }
                guard Set(names).count == names.count else { throw ClementineError.message("Two selected files have the same name. Move them separately to avoid a collision.") }
                for url in files.urls {
                    let out = destination.appendingPathComponent(url.lastPathComponent)
                    if out.standardizedFileURL == url.standardizedFileURL { continue }
                    guard !FileManager.default.fileExists(atPath:out.path) else { throw ClementineError.message("\(out.lastPathComponent) already exists. No files will be overwritten.") }
                }
                for url in files.urls { let out = destination.appendingPathComponent(url.lastPathComponent); if out.standardizedFileURL != url.standardizedFileURL { try FileManager.default.moveItem(at:url,to:out);moved.append((url,out)) } }
            } catch {
                var remaining:[String] = []
                for (original,current) in moved.reversed() { do { try FileManager.default.moveItem(at:current,to:original) } catch { remaining.append(current.path) } }
                errorText = error.localizedDescription + (remaining.isEmpty ? "" : "\nThese files remain at their new locations: " + remaining.joined(separator:", "))
                openWindow()
            }
        case "terminal":
            let paths = Set(files.urls.map { url -> URL in var directory:ObjCBool = false; FileManager.default.fileExists(atPath:url.path,isDirectory:&directory); return directory.boolValue ? url : url.deletingLastPathComponent() })
            for path in paths { NSWorkspace.shared.open([path],withApplicationAt:URL(fileURLWithPath:"/System/Applications/Utilities/Terminal.app"),configuration:NSWorkspace.OpenConfiguration()) }
        default: break
        }
    }
}
