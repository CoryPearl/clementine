import SwiftUI
import AppKit
import ApplicationServices
import ServiceManagement

let orange = Color(red:0.97,green:0.36,blue:0.08)
let ink = Color(red:0.29,green:0.16,blue:0.10)
let paper = Color(red:0.985,green:0.975,blue:0.948)

struct HomeView:View {
    @ObservedObject var app:AppController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var category:Category?
    var body:some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:24) {
                HStack(spacing:10) { Image(systemName:"circle.hexagongrid.fill").font(.system(size:30)).foregroundStyle(orange); Text("clementine").font(.system(size:23,weight:.semibold,design:.rounded)).tracking(-0.8) }.padding(.top,22)
                Text("A little less busywork.").font(.system(size:12)).foregroundStyle(.secondary)
                VStack(spacing:6) {
                    sideButton("Workspace","square.grid.2x2",selected:!app.showSettings) { app.showSettings = false }
                    sideButton("Settings","slider.horizontal.3",selected:app.showSettings) { app.showSettings = true }
                }
                Divider()
                Text("MADE FOR YOUR FLOW").font(.system(size:9,weight:.bold)).tracking(1.5).foregroundStyle(.secondary)
                shortcut("⇧","Convert", "Change the format")
                shortcut("⌘","Tools", "Make it your own")
                shortcut("⌃","Actions", "Put it in its place")
                Spacer()
                HStack(spacing:6) { Circle().fill(Color.green).frame(width:6,height:6); Text("Everything stays on your Mac").font(.system(size:10)) }.foregroundStyle(.secondary)
                Text("CLEMENTINE / 1.1").font(.system(size:9,weight:.medium,design:.monospaced)).tracking(1.6).foregroundStyle(.tertiary)
            }.padding(24).frame(width:240).background(SidebarGlassBackground()).overlay(alignment:.trailing) { Rectangle().fill(.white.opacity(0.55)).frame(width:1).allowsHitTesting(false) }
            if app.showSettings { SettingsView(app:app) }
            else {
                ScrollView {
                    VStack(alignment:.leading,spacing:25) {
                        HStack { VStack(alignment:.leading,spacing:6) { Text("Good things, fewer steps.").font(.system(size:30,weight:.medium,design:.serif)).tracking(-0.6); Text("Drop a file. Pick a possibility.").font(.system(size:13)).foregroundStyle(.secondary) }; Spacer(); Button { app.chooseFiles() } label:{ Label("Add files",systemImage:"plus").font(.system(size:12,weight:.medium)) }.buttonStyle(.bordered) }
                        dropArea
                        if !app.selection.urls.isEmpty { operations }
                        else { categories }
                        if !app.jobs.isEmpty {
                            HStack { Text("RECENT ACTIVITY").font(.system(size:10,weight:.bold)).tracking(1.5); Spacer(); Button("Clear finished") { app.jobs.removeAll { $0.state != .running && $0.state != .queued } }.font(.system(size:11)) }
                            VStack(spacing:1) { ForEach(app.jobs) { job in JobRow(job:job) } }.clementineGlass(radius:16)
                        }
                        if let error = app.errorText { Text(error).font(.system(size:12)).foregroundStyle(.red).textSelection(.enabled); Button("Dismiss") { app.errorText = nil } }
                    }.padding(32).padding(.top,18)
                }.frame(maxWidth:.infinity,maxHeight:.infinity).background(OrangeGlassBackdrop())
            }
        }.foregroundStyle(ink).frame(maxWidth:.infinity,maxHeight:.infinity).background(OrangeGlassBackdrop()).tint(orange).preferredColorScheme(.light)
            .animation(reduceMotion ? nil : .easeInOut(duration:0.18),value:app.showSettings)
            .animation(reduceMotion ? nil : .spring(response:0.3,dampingFraction:0.84),value:app.mode)
    }
    func sideButton(_ text:String,_ symbol:String,selected:Bool,action:@escaping()->Void)->some View {
        Button(action:action) { HStack(spacing:10) { Image(systemName:symbol).frame(width:18); Text(text); Spacer(); if selected { Circle().fill(orange).frame(width:5,height:5) } }.font(.system(size:12,weight:selected ? .semibold : .regular)).padding(11).background(selected ? orange.opacity(0.13) : .clear).clipShape(RoundedRectangle(cornerRadius:8)) }.buttonStyle(.plain)
    }
    func shortcut(_ key:String,_ title:String,_ sub:String)->some View { HStack(spacing:12) { Text(key).font(.system(size:18,weight:.medium)).frame(width:34,height:34).foregroundStyle(orange).clementineGlass(radius:10); VStack(alignment:.leading,spacing:3) { Text(title).font(.system(size:12,weight:.medium)); Text(sub).font(.system(size:10)).foregroundStyle(.secondary) } } }
    var dropArea:some View {
        VStack(spacing:12) {
            ZStack { Circle().fill(orange.opacity(0.09)).frame(width:72,height:72); Image(systemName:app.selection.urls.isEmpty ? "arrow.down.doc" : app.selection.category.symbol).font(.system(size:28,weight:.light)).foregroundStyle(orange) }
            Text(app.selection.urls.isEmpty ? "Drop something here" : app.selection.label).font(.system(size:17,weight:.medium,design:.rounded)).lineLimit(1)
            Text(app.selection.urls.isEmpty ? "Images, videos, audio, documents, and the rest." : app.selection.urls.prefix(3).map(\.lastPathComponent).joined(separator:"  ·  ")).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2)
            if !app.selection.urls.isEmpty { Button("Choose different files") { app.chooseFiles() }.font(.system(size:10)).buttonStyle(.plain).foregroundStyle(orange) }
        }.frame(maxWidth:.infinity).padding(.vertical,28)
            .background(hovering ? orange.opacity(0.15) : Color.white.opacity(0.08)).clementineGlass(radius:22)
            .scaleEffect(hovering && !reduceMotion ? 1.012 : 1)
            .animation(reduceMotion ? nil : .spring(response:0.3,dampingFraction:0.82),value:hovering)
            .overlay(RoundedRectangle(cornerRadius:22).strokeBorder(orange.opacity(hovering ? 0.65 : 0.2),style:StrokeStyle(lineWidth:1,dash:[5,5])))
            .onDrop(of:["public.file-url"],isTargeted:$hovering) { providers in
                let group = DispatchGroup(); let lock = NSLock(); var values:[Int:URL] = [:]
                for (i,provider) in providers.enumerated() { group.enter(); provider.loadItem(forTypeIdentifier:"public.file-url",options:nil) { item,_ in defer { group.leave() }; let u = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation:$0,relativeTo:nil) }; if let u { lock.lock(); values[i] = u; lock.unlock() } } }
                group.notify(queue:.main) { app.accept(values.sorted { $0.key < $1.key }.map(\.value)) }; return true
            }
            .onTapGesture { if app.selection.urls.isEmpty { app.chooseFiles() } }
    }
    var operations:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { ForEach(WheelMode.allCases,id:\.self) { mode in Button { app.mode = mode } label:{ Text(mode.rawValue).font(.system(size:12,weight:.medium)).padding(.horizontal,16).padding(.vertical,8).background(app.mode == mode ? orange : Color.clear).foregroundStyle(app.mode == mode ? Color.white : ink).clipShape(Capsule()) }.buttonStyle(.plain) }; Spacer(); Button { app.selection = FileSelection(urls:[]) } label:{ Image(systemName:"xmark").font(.system(size:10)) }.buttonStyle(.plain) }
            let options = Registry.operations(app.mode,app.selection)
            if options.isEmpty { Text("This selection has no \(app.mode.rawValue.lowercased()). Try Actions for mixed selections and folders.").font(.system(size:12)).foregroundStyle(.secondary) }
            LazyVGrid(columns:[GridItem(.adaptive(minimum:130),spacing:10)],spacing:10) {
                ForEach(options) { operation in Button { app.invoke(operation) } label:{ HStack { Image(systemName:operation.symbol).font(.system(size:14)).foregroundStyle(orange); Text(operation.title).font(.system(size:11,weight:.medium)).lineLimit(1); Spacer() }.padding(13).frame(maxWidth:.infinity).clementineGlass(radius:12) }.buttonStyle(.plain).help(operation.detail) }
            }
        }
    }
    var categories:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("ALL YOUR FILES. ONE LITTLE APP.").font(.system(size:10,weight:.bold)).tracking(1.4).foregroundStyle(.secondary)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:100),alignment:.leading)],alignment:.leading,spacing:16) { ForEach(Category.allCases.filter { $0 != .other },id:\.self) { category in HStack(spacing:7) { Image(systemName:category.symbol).foregroundStyle(orange.opacity(0.8)); Text(category.title).font(.system(size:11)) } } }
            HStack(alignment:.top,spacing:12) { Image(systemName:"sparkle").foregroundStyle(orange); Text("You can also drag a file anywhere on your Mac and tap Shift, Command, or Control to open the wheel.").font(.system(size:12)).lineSpacing(4).foregroundStyle(.secondary) }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(orange.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius:10))
        }
    }
}
struct JobRow:View {
    @ObservedObject var job:Job
    var body:some View {
        HStack(spacing:12) {
            if job.state == .running || job.state == .queued { ProgressView().controlSize(.small) }
            else { Image(systemName:job.state == .completed ? "checkmark.circle.fill" : job.state == .cancelled ? "xmark.circle" : "exclamationmark.circle.fill").foregroundStyle(job.state == .completed ? .green : .secondary) }
            VStack(alignment:.leading,spacing:4) { Text("\(job.operation) · \(job.name)").font(.system(size:12,weight:.medium)).lineLimit(1); Text(job.message).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(job.state == .failed ? 5 : 1).textSelection(.enabled) }
            Spacer()
            if job.state == .running || job.state == .queued { Button("Cancel") { job.token.cancel() }.font(.system(size:10)) }
            if !job.outputs.isEmpty { Button { NSWorkspace.shared.activateFileViewerSelecting(job.outputs) } label:{ Image(systemName:"folder") }.buttonStyle(.plain).help("Show in Finder") }
        }.padding(14)
    }
}
struct SettingsView:View {
    @ObservedObject var app:AppController
    @AppStorage("quality") var quality = 82.0
    @AppStorage("sound") var sound = false
    @AppStorage("outputFolder") var outputFolder = ""
    @AppStorage("convertKey") var convertKey = "Shift"
    @AppStorage("toolsKey") var toolsKey = "Command"
    @AppStorage("actionsKey") var actionsKey = "Control"
    @State var trusted = AXIsProcessTrusted()
    @State var login = SMAppService.mainApp.status == .enabled
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                Text("A few finishing touches.").font(.system(size:29,weight:.medium,design:.serif))
                GroupBox("Drag wheel") { VStack(alignment:.leading,spacing:12) {
                    keyPicker("Conversions",value:$convertKey); keyPicker("File tools",value:$toolsKey); keyPicker("File actions",value:$actionsKey)
                    if Set([convertKey,toolsKey,actionsKey]).count < 3 { Text("Choose a different key for each wheel.").foregroundStyle(.red).font(.caption) }
                    Text("Tap a key while dragging. Release the key, choose a segment, and drop. Escape cancels.").font(.caption).foregroundStyle(.secondary)
                }.padding(10) }
                GroupBox("Output") { VStack(alignment:.leading,spacing:12) { HStack { Text("Default quality"); Slider(value:$quality,in:10...100); Text("\(Int(quality))%").monospacedDigit().frame(width:40) }; Toggle("Play a sound when finished",isOn:$sound); HStack { Text(outputFolder.isEmpty ? "Save beside the original" : outputFolder).font(.caption).lineLimit(1).truncationMode(.middle); Spacer(); Button("Choose folder…") { let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; if p.runModal() == .OK { outputFolder = p.url!.path } }; if !outputFolder.isEmpty { Button("Reset") { outputFolder = "" } } } }.padding(10) }
                GroupBox("System integration") { VStack(alignment:.leading,spacing:12) {
                    Toggle("Launch Clementine at login",isOn:$login).onChange(of:login) { value in do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { app.errorText = error.localizedDescription } }
                    HStack { Image(systemName:trusted ? "checkmark.shield" : "hand.raised"); Text(trusted ? "Accessibility is enabled" : "Enable Accessibility for global keyboard control"); Spacer(); Button("Enable…") { let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true]; _ = AXIsProcessTrustedWithOptions(options as CFDictionary); trusted = AXIsProcessTrusted() } }
                    Text("Pages, Numbers, and Keynote may request Automation permission when converting their native documents.").font(.caption).foregroundStyle(.secondary)
                }.padding(10) }
                GroupBox("About Clementine") { VStack(alignment:.leading,spacing:10) { Text("Version 1.1 · Native Swift · All processing happens on your Mac").font(.caption); Text("Clementine uses FFmpeg, ImageMagick, ExifTool, Pandoc, librsvg, LibreOffice, and their open-source dependencies.").font(.caption).foregroundStyle(.secondary); Button("Third-party notices") { let u = Bundle.main.resourceURL!.appendingPathComponent("Licenses"); NSWorkspace.shared.open(u) } }.padding(10).frame(maxWidth:.infinity,alignment:.leading) }
            }.padding(32).padding(.top,18)
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(OrangeGlassBackdrop()).font(.system(size:12))
    }
    func keyPicker(_ label:String,value:Binding<String>)->some View { HStack { Text(label); Spacer(); Picker(label,selection:value) { ForEach(["Shift","Command","Control","Option"],id:\.self) { Text($0) } }.labelsHidden().frame(width:130) } }
}
