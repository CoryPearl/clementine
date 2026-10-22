import SwiftUI
import AppKit
import AVKit
import PDFKit
import CoreImage

@MainActor final class EditorModel:ObservableObject {
    let operation:OperationDescriptor; let files:FileSelection; let tool:Tool
    @Published var options = OperationOptions()
    @Published var image:NSImage?; @Published var waveform:NSImage?; @Published var player:AVPlayer?
    @Published var pixelSize = CGSize(width:16,height:9)
    @Published var duration = 0.0; @Published var message = ""; @Published var busy = false
    @Published var metadata = ""; @Published var pdf:PDFDocument?; @Published var page = 0
    @Published var previewImage:NSImage?; @Published var previewPlayer:AVPlayer?
    var previewDirectory:URL?; var previewToken:CancellationToken?
    init(operation:OperationDescriptor,files:FileSelection) {
        self.operation = operation; self.files = files; tool = Tool(rawValue:String(operation.id.dropFirst(5)))!
        options.quality = UserDefaults.standard.double(forKey:"quality"); if options.quality <= 0 { options.quality = 82 }
        if let path = UserDefaults.standard.string(forKey:"outputFolder"),!path.isEmpty { options.destination = URL(fileURLWithPath:path) }
        let input = files.urls[0]
        if files.category == .image {
            image = NSImage(contentsOf:input)
            if let cg = image?.cgImage(forProposedRect:nil,context:nil,hints:nil) { options.width = cg.width; options.height = cg.height; pixelSize = CGSize(width:cg.width,height:cg.height) }
            if tool != .cropImage && tool != .compress { options.width = 0; options.height = 0 }
        }
        if files.category == .pdf { pdf = PDFDocument(url:input); options.pageOrder = "" }
        if [.audio,.video].contains(files.category) { player = AVPlayer(url:input) }
        loadInfo()
    }
    deinit { previewToken?.cancel(); if let previewDirectory { try? FileManager.default.removeItem(at:previewDirectory) } }
    func loadInfo() {
        let input = files.urls[0],category = files.category,tool = tool
        Task {
            let data = await Task.detached { () -> (Double,String,Data?,CGSize) in
                let engine = Engine(token:CancellationToken()); let duration = [.audio,.video].contains(category) ? engine.duration(input) : 0
                let metadata = tool == .metadata ? (try? engine.run(engine.tool("exiftool"),["-G","-s",input.path])) ?? "" : ""
                var wave:Data?
                if category == .audio {
                    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("wave-\(UUID().uuidString).png")
                    try? engine.ff(["-i",input.path,"-filter_complex","showwavespic=s=1000x180:colors=0xf56d29","-frames:v","1",temp.path]); wave = try? Data(contentsOf:temp); try? FileManager.default.removeItem(at:temp)
                }
                let info = category == .video ? try? engine.probe(input) : nil
                let stream = (info?["streams"] as? [[String:Any]])?.first { $0["codec_type"] as? String == "video" }
                let size = CGSize(width:stream?["width"] as? Int ?? 16,height:stream?["height"] as? Int ?? 9)
                return (duration,metadata,wave,size)
            }.value
            duration = data.0; metadata = data.1; waveform = data.2.flatMap { NSImage(data:$0) }; if files.category == .video { pixelSize = data.3 }
            if duration > 0 { options.end = duration }
        }
    }
    func detect(faces:Bool) {
        busy = true; let url = files.urls[0]
        Task { do { let rects = try await Task.detached { try Engine(token:CancellationToken()).detectRegions(url,faces:faces) }.value; options.rectangles.append(contentsOf:rects); message = "Found \(rects.count) areas. Review before exporting." } catch { message = error.localizedDescription }; busy = false }
    }
    func qr() {
        let url = files.urls[0]; Task { do { let text = try await Task.detached { try Engine(token:CancellationToken()).readQRCode(url) }.value; message = text; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType:.string) } catch { message = error.localizedDescription } }
    }
    func addRectangle(_ r:CGRect) {
        if tool == .cropImage || tool == .cropVideo {
            options.rectangles = [r]
            if let cg = image?.cgImage(forProposedRect:nil,context:nil,hints:nil) { options.cropX = Int(r.minX*Double(cg.width)); options.cropY = Int(r.minY*Double(cg.height)); options.width = Int(r.width*Double(cg.width)); options.height = Int(r.height*Double(cg.height)) }
            else if files.category == .video {
                options.cropX = Int(r.minX*pixelSize.width); options.cropY = Int(r.minY*pixelSize.height)
                options.width = Int(r.width*pixelSize.width); options.height = Int(r.height*pixelSize.height)
            }
        } else { options.rectangles.append(r) }
    }
    func preview() {
        guard !busy else { return }; busy = true; message = "Rendering preview…"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Clementine-preview-\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true) } catch { busy = false; message = error.localizedDescription; return }
        if let previewDirectory { try? FileManager.default.removeItem(at:previewDirectory) }; previewDirectory = directory
        var o = options; o.destination = directory
        if [.video,.audio].contains(files.category) { o.end = min(options.start+8,options.end > options.start ? options.end : duration) }
        let request = ConversionRequest(urls:files.urls,operation:operation.id,options:o), token = CancellationToken(); previewToken = token
        Task { do {
            let urls = try await Task.detached { try Engine(token:token).execute(request) { _,_ in } }.value
            if let url = urls.first {
                if Registry.category(url) == .image { previewImage = NSImage(contentsOf:url) }
                else if [.video,.audio].contains(Registry.category(url)) { previewPlayer = AVPlayer(url:url); previewPlayer?.play() }
                else if Registry.category(url) == .pdf { pdf = PDFDocument(url:url) }
            }; message = "Preview rendered. Export applies these settings to the full selection."
        } catch { message = error.localizedDescription }; busy = false }
    }
}
struct PlayerView:NSViewRepresentable {
    let player:AVPlayer
    func makeNSView(context:Context)->AVPlayerView { let v = AVPlayerView(); v.player = player; v.controlsStyle = .floating; v.showsFullScreenToggleButton = false; v.videoGravity = .resizeAspect; return v }
    func updateNSView(_ v:AVPlayerView,context:Context) { v.player = player }
}
struct EditorView:View {
    @ObservedObject var model:EditorModel
    let export:(OperationOptions)->Void
    @State var drawing:CGRect?; @State var draggingPage:Int?
    var isDrawing:Bool { [.annotateImage,.redactImage,.redactVideo,.cropImage,.cropVideo].contains(model.tool) }
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:12) { Image(systemName:model.operation.symbol).font(.system(size:22)).foregroundStyle(orange); VStack(alignment:.leading,spacing:3) { Text(model.operation.title).font(.system(size:18,weight:.semibold,design:.rounded)); Text(model.files.label).font(.system(size:11)).foregroundStyle(.secondary) }; Spacer(); if model.files.urls.count > 1 { Text("Applies to \(model.files.urls.count) files").font(.system(size:11)).foregroundStyle(.secondary) } }.padding(22)
            Divider()
            HStack(spacing:0) {
                VStack(spacing:12) {
                    preview.frame(maxWidth:.infinity,maxHeight:.infinity).background(orange.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius:12))
                    if [.audio,.video].contains(model.files.category) { timeline }
                    if isDrawing { HStack { Text("Drag on the preview to \(model.tool == .cropImage || model.tool == .cropVideo ? "select a crop" : "mark an area").").font(.system(size:10)).foregroundStyle(.secondary); Spacer(); Button("Undo") { if !model.options.rectangles.isEmpty { model.options.rectangles.removeLast() } }; Button("Clear") { model.options.rectangles = []; model.previewImage = nil } }.font(.system(size:10)) }
                    if !model.message.isEmpty { ScrollView { Text(model.message).font(.system(size:11)).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }.frame(maxHeight:60) }
                }.padding(20)
                Divider()
                ScrollView { VStack(alignment:.leading,spacing:18) { controls }.padding(20) }.frame(width:295)
            }
            Divider()
            HStack { Image(systemName:"lock.shield").foregroundStyle(.secondary); Text("Originals stay unchanged").font(.system(size:11)).foregroundStyle(.secondary); Spacer(); if model.busy { ProgressView().controlSize(.small) }; Button("Preview result") { model.preview() }.disabled(model.busy); Button("Export \(model.files.urls.count == 1 ? "file" : "\(model.files.urls.count) files")") { model.player?.pause(); model.previewPlayer?.pause(); export(model.options) }.buttonStyle(.borderedProminent).disabled(model.busy) }.padding(18)
        }.background(OrangeGlassBackdrop()).foregroundStyle(ink).tint(orange).preferredColorScheme(.light)
        .onDisappear { model.player?.pause(); model.previewPlayer?.pause(); model.previewToken?.cancel() }
    }
    @ViewBuilder var preview:some View {
        if let image = model.previewImage ?? model.image {
            GeometryReader { geo in
                let size = image.size; let factor = min(geo.size.width/max(1,size.width),geo.size.height/max(1,size.height)); let w = size.width*factor,h = size.height*factor
                ZStack {
                    if model.tool == .frameImage { Color(cgColor:Engine(token:CancellationToken()).hexColor(model.options.background)) }
                    Image(nsImage:image).resizable().aspectRatio(contentMode:.fit)
                    drawingLayer(w:w,h:h)
                }.frame(width:w,height:h).position(x:geo.size.width/2,y:geo.size.height/2)
            }
        } else if let pdf = model.pdf { pdfPages(pdf) }
        else if let player = model.previewPlayer ?? model.player {
            VStack(spacing:0) {
                if let waveform = model.waveform { Image(nsImage:waveform).resizable().aspectRatio(contentMode:.fit).padding(20) }
                ZStack {
                    PlayerView(player:player)
                    if isDrawing { GeometryReader { g in
                        let f = min(g.size.width/model.pixelSize.width,g.size.height/model.pixelSize.height)
                        drawingLayer(w:model.pixelSize.width*f,h:model.pixelSize.height*f).position(x:g.size.width/2,y:g.size.height/2)
                    } }
                }
            }
        } else { VStack(spacing:12) { Image(nsImage:NSWorkspace.shared.icon(forFile:model.files.urls[0].path)).resizable().frame(width:90,height:90); Text(model.files.label).font(.caption) } }
    }
    @ViewBuilder func drawingLayer(w:CGFloat,h:CGFloat)->some View {
        if isDrawing && model.previewImage == nil {
            ZStack {
                ForEach(Array(model.options.rectangles.enumerated()),id:\.offset) { i,r in
                    let rect = CGRect(x:r.minX*w,y:r.minY*h,width:r.width*w,height:r.height*h)
                    Rectangle().fill(model.tool == .redactImage || model.tool == .redactVideo ? Color.black.opacity(0.85) : orange.opacity(0.13)).overlay(Rectangle().strokeBorder(orange,lineWidth:2)).frame(width:rect.width,height:rect.height).position(x:rect.midX,y:rect.midY)
                }
                if let drawing { Rectangle().strokeBorder(orange,style:StrokeStyle(lineWidth:2,dash:[5])).background(orange.opacity(0.1)).frame(width:drawing.width*w,height:drawing.height*h).position(x:drawing.midX*w,y:drawing.midY*h) }
                Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:3).onChanged { value in drawing = normalized(value,w:w,h:h) }.onEnded { value in if let r = normalized(value,w:w,h:h),r.width > 0.005,r.height > 0.005 { model.addRectangle(r) }; drawing = nil })
            }.frame(width:w,height:h)
        }
    }
    func normalized(_ value:DragGesture.Value,w:CGFloat,h:CGFloat)->CGRect? {
        guard w > 0,h > 0 else { return nil }; let x1 = max(0,min(1,value.startLocation.x/w)),y1 = max(0,min(1,value.startLocation.y/h)),x2 = max(0,min(1,value.location.x/w)),y2 = max(0,min(1,value.location.y/h))
        return CGRect(x:min(x1,x2),y:min(y1,y2),width:abs(x2-x1),height:abs(y2-y1))
    }
    func pdfPages(_ pdf:PDFDocument)->some View {
        ScrollView { LazyVGrid(columns:[GridItem(.adaptive(minimum:120))],spacing:16) {
            let order = (try? Engine(token:CancellationToken()).pageIndices(model.options.pageOrder,count:pdf.pageCount)) ?? Array(0..<pdf.pageCount)
            ForEach(Array(order.enumerated()),id:\.offset) { position,i in
                if let original = pdf.page(at:i),let page = original.copy() as? PDFPage {
                    let _ = page.rotation += model.options.pageRotations[i] ?? 0
                    VStack { Image(nsImage:page.thumbnail(of:NSSize(width:200,height:260),for:.mediaBox)).resizable().aspectRatio(contentMode:.fit).shadow(color:.black.opacity(0.1),radius:3); Text("Page \(i+1)").font(.system(size:10)) }.padding(10)
                        .onDrag { draggingPage = position; return NSItemProvider(object:String(position) as NSString) }
                        .onDrop(of:["public.text"],isTargeted:nil) { _ in
                            guard let source = draggingPage else { return false }
                            var order = (try? Engine(token:CancellationToken()).pageIndices(model.options.pageOrder,count:pdf.pageCount)) ?? Array(0..<pdf.pageCount)
                            if order.indices.contains(source),order.indices.contains(position) { let moved = order.remove(at:source);order.insert(moved,at:position);model.options.pageOrder = order.map { String($0+1) }.joined(separator:",") }
                            draggingPage = nil; return true
                        }
                        .onTapGesture { model.page = i }
                        .contextMenu {
                            Button("Rotate clockwise") { model.options.pageRotations[i] = ((model.options.pageRotations[i] ?? 0)+90)%360 }
                            Button("Remove page") { var pages = order;pages.remove(at:position);if !pages.isEmpty { model.options.pageOrder = pages.map { String($0+1) }.joined(separator:",") } }
                        }
                }
            }
        }.padding(20) }
    }
    var timeline:some View {
        VStack(spacing:10) {
            HStack { Text("START").font(.system(size:9,weight:.bold)).tracking(1); TextField("0",value:$model.options.start,format:.number.precision(.fractionLength(2))).frame(width:70); Spacer(); Text("END").font(.system(size:9,weight:.bold)).tracking(1); TextField("End",value:$model.options.end,format:.number.precision(.fractionLength(2))).frame(width:70); Text("seconds").font(.system(size:10)).foregroundStyle(.secondary) }
            if model.duration > 0 {
                Slider(value:$model.options.start,in:0...model.duration).onChange(of:model.options.start) { v in model.player?.seek(to:CMTime(seconds:v,preferredTimescale:600)) }
                Slider(value:$model.options.end,in:0...model.duration)
            }
        }.textFieldStyle(.roundedBorder).font(.system(size:11))
    }
    @ViewBuilder var controls:some View {
        Text("MAKE IT YOURS").font(.system(size:9,weight:.bold)).tracking(1.5).foregroundStyle(.secondary)
        switch model.tool {
        case .compress:
            slider("Quality",value:$model.options.quality,range:10...100)
            number("Target size (KB, 0 = auto)",value:$model.options.targetKB)
            if model.files.category == .image || model.files.category == .video { dimensions }
            if model.files.category == .pdf { note("PDF compression rasterizes pages at 100–150 DPI. Text selection and search are lost in the compressed copy.") }
        case .metadata:
            Toggle("Remove all metadata",isOn:$model.options.removeMetadata)
            if model.files.category == .pdf && model.options.removeMetadata { note("Rewrites the PDF and flattens annotations to remove embedded metadata. The original stays unchanged.") }
            if !model.options.removeMetadata { TextField("Author",text:$model.options.author); TextField("Title",text:$model.options.title)
                ForEach(["Make","Model","LensModel","Artist","Copyright","GPSLatitude","GPSLatitudeRef","GPSLongitude","GPSLongitudeRef","Software","Description"],id:\.self) { key in
                    TextField(key,text:Binding(get:{ model.options.metadataTags[key] ?? "" },set:{ model.options.metadataTags[key] = $0 }))
                } }
            Text("CURRENT METADATA").font(.system(size:9,weight:.bold)).foregroundStyle(.secondary)
            Text(model.metadata.isEmpty ? "Reading…" : model.metadata).font(.system(size:9,design:.monospaced)).textSelection(.enabled)
        case .editImage:
            slider("Exposure",value:$model.options.exposure,range:-3...3); slider("Saturation",value:$model.options.saturation,range:0...2); slider("Contrast",value:$model.options.contrast,range:0.5...2)
            slider("Temperature",value:$model.options.temperature,range:-1...1); slider("Sharpness",value:$model.options.sharpness,range:0...3); slider("Vignette",value:$model.options.vignette,range:0...1)
            Picker("Effect",selection:$model.options.effect) { ForEach(["None","Grayscale","Sepia"],id:\.self) { Text($0) } }
            Toggle("Flip horizontally",isOn:$model.options.flipHorizontal); Toggle("Flip vertically",isOn:$model.options.flipVertical); rotation
        case .annotateImage:
            Picker("Annotation",selection:$model.options.annotationStyle) { ForEach(["Text","Arrow","Rectangle","Ellipse","Number"],id:\.self) { Text($0) } }
            if model.options.annotationStyle == "Text" { TextField("Your annotation",text:$model.options.annotation); slider("Font size",value:$model.options.annotationSize,range:12...160) }
            TextField("Color hex",text:$model.options.background)
            note("Draw a rectangle to position each annotation. Arrows point from the lower left to the upper right.")
        case .frameImage:
            TextField("Background hex",text:$model.options.background)
            Toggle("Gradient",isOn:$model.options.gradient)
            if model.options.gradient { TextField("Second color hex",text:$model.options.secondaryBackground) }
            Picker("Canvas",selection:$model.options.aspect) { ForEach(["Original","Square","Landscape","Portrait","4:3"],id:\.self) { Text($0) } }
            integer("Padding",value:$model.options.padding); slider("Corner radius",value:$model.options.radius,range:0...200)
            Button("Use an image background…") { let p = NSOpenPanel(); p.allowedContentTypes = [.image]; if p.runModal() == .OK { model.options.backgroundImage = p.url!.path } }
        case .cropImage,.cropVideo:
            dimensions; integer("Left (pixels)",value:$model.options.cropX); integer("Top (pixels)",value:$model.options.cropY)
            note("Draw on the preview or enter exact pixel coordinates.")
        case .normalizeAudio: note("Normalizes loudness to −16 LUFS, with a −1.5 dB true-peak ceiling. Listen to a preview before exporting.")
        case .audioChannels:
            Picker("Output",selection:$model.options.channels) { Text("Mono").tag(1); Text("Stereo").tag(2) }; slider("Gain (dB)",value:$model.options.gain,range:-24...12)
        case .trimAudio,.trimVideo: note("Set the start and end below the preview. The original file is preserved.")
        case .changeVideoSpeed: slider("Playback speed",value:$model.options.speed,range:0.25...4); note("Audio pitch is preserved when changing speed.")
        case .splitVideo: TextField("Seconds: 5, 12.5, 30",text:$model.options.splitTimes); note("Enter split points separated by commas. Each remaining segment is exported as a separate file.")
        case .videoSnapshots: TextField("Seconds: 0, 5, 10",text:$model.options.splitTimes); note("Leave blank to export the frame at the Start time. Frames are saved as PNG files.")
        case .audioToVideo: Picker("Visualization",selection:$model.options.visualizer) { Text("Waveform").tag("Waveform"); Text("Spectrum").tag("Spectrum") }; note("Creates a 1280 × 720 MP4 with the original audio.")
        case .redactImage,.redactVideo:
            if model.tool == .redactImage { Toggle("Blur marked areas",isOn:$model.options.blur); Button("Detect faces") { model.detect(faces:true) }; Button("Detect text") { model.detect(faces:false) }; Button("Read QR / barcode") { model.qr() } }
            else { TextField("Time ranges: 1-3, 8-10",text:$model.options.redactRanges); note("Blank time ranges cover marked areas throughout the video.") }
            note("Review all marked areas. Solid fills provide stronger concealment than blur. Export creates a flattened copy.")
        case .redactAudio: TextField("Time ranges: 1-3, 8-10",text:$model.options.redactRanges); note("Replaces the chosen ranges with a 1 kHz tone.")
        case .splitPDF,.organizePDF:
            TextField("Pages: 1, 3-5, 2",text:$model.options.pageOrder); note("Blank means all pages. Enter page numbers and ranges in the desired order; omit pages to remove them.")
            if model.tool == .splitPDF { Toggle("Keep each range together",isOn:$model.options.splitGroups) } else { rotation }
        default: EmptyView()
        }
        Divider()
        Text("SAVE TO").font(.system(size:9,weight:.bold)).tracking(1).foregroundStyle(.secondary)
        Text(model.options.destination?.path ?? "Beside the original").font(.system(size:10)).foregroundStyle(.secondary).lineLimit(3).truncationMode(.middle)
        Button("Choose folder…") { let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; if p.runModal() == .OK { model.options.destination = p.url } }
    }
    var dimensions:some View { VStack(alignment:.leading,spacing:12) { integer("Width (pixels)",value:$model.options.width); integer("Height (pixels)",value:$model.options.height) } }
    var rotation:some View { Picker("Rotation",selection:$model.options.rotation) { Text("0°").tag(0.0); Text("90°").tag(90.0); Text("180°").tag(180.0); Text("270°").tag(270.0) } }
    func integer(_ title:String,value:Binding<Int>)->some View { VStack(alignment:.leading,spacing:5) { Text(title).font(.system(size:11)); TextField(title,value:value,format:.number).textFieldStyle(.roundedBorder) } }
    func number(_ title:String,value:Binding<Double>)->some View { VStack(alignment:.leading,spacing:5) { Text(title).font(.system(size:11)); TextField(title,value:value,format:.number).textFieldStyle(.roundedBorder) } }
    func slider(_ title:String,value:Binding<Double>,range:ClosedRange<Double>)->some View { VStack(alignment:.leading,spacing:8) { HStack { Text(title); Spacer(); Text(value.wrappedValue,format:.number.precision(.fractionLength(1))).foregroundStyle(.secondary).monospacedDigit() }; Slider(value:value,in:range) }.font(.system(size:11)) }
    func note(_ text:String)->some View { Text(text).font(.system(size:11)).foregroundStyle(.secondary).lineSpacing(4) }
}
