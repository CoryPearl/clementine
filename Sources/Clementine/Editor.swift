import SwiftUI
import AppKit
import AVKit
import PDFKit
import CoreImage

struct PlayerView:NSViewRepresentable {
    let player:AVPlayer
    var audioOnly = false
    func makeNSView(context:Context)->AVPlayerView { let v = AVPlayerView(); v.player = player; v.controlsStyle = audioOnly ? .inline : .floating; v.showsFullScreenToggleButton = false; v.videoGravity = .resizeAspect; return v }
    func updateNSView(_ v:AVPlayerView,context:Context) { v.player = player }
}
struct EditorView:View {
    @ObservedObject var model:EditorModel
    let export:(OperationOptions)->Void
    @State var drawing:CGRect?; @State var draggingPage:Int?
    var isDrawing:Bool { [.annotateImage,.redactImage,.redactVideo].contains(model.tool) }
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:12) { Image(systemName:model.operation.symbol).font(.system(size:22)).foregroundStyle(orange); VStack(alignment:.leading,spacing:3) { Text(model.operation.title).font(.system(size:18,weight:.semibold,design:.rounded)); Text(model.files.label).font(.system(size:11)).foregroundStyle(.secondary) }; Spacer(); if model.files.urls.count > 1 { Text("Applies to \(model.files.urls.count) files").font(.system(size:11)).foregroundStyle(.secondary) } }.padding(22)
            Divider()
            HStack(spacing:0) {
                VStack(spacing:12) {
                    canvas.frame(maxWidth:.infinity,maxHeight:.infinity).background(orange.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius:12))
                    if [.audio,.video].contains(model.files.category) { timeline }
                    if isDrawing { HStack { Text("Drag on the canvas to mark an area.").font(.system(size:10)).foregroundStyle(.secondary); Spacer(); Button("Undo") { if !model.options.rectangles.isEmpty { model.options.rectangles.removeLast() } }; Button("Clear") { model.options.rectangles = [] } }.font(.system(size:10)) }
                    if let error = model.validationMessage { Text(error).font(.system(size:11)).foregroundStyle(.red).frame(maxWidth:.infinity,alignment:.leading) }
                    if !model.backgroundError.isEmpty { Text(model.backgroundError).font(.system(size:11)).foregroundStyle(.red).frame(maxWidth:.infinity,alignment:.leading) }
                    if !model.message.isEmpty { ScrollView { Text(model.message).font(.system(size:11)).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }.frame(maxHeight:60) }
                }.padding(20)
                Divider()
                ScrollView { VStack(alignment:.leading,spacing:18) { controls }.padding(20) }.frame(width:295)
            }
            Divider()
            HStack(spacing:12) {
                Image(systemName:"lock.shield").foregroundStyle(.secondary)
                Text("Originals stay unchanged").font(.system(size:11)).foregroundStyle(.secondary)
                if model.files.category == .image && model.tool != .metadata { Toggle("Original",isOn:$model.showOriginal).toggleStyle(.button).font(.system(size:11)).help("Compare with the original image") }
                Spacer()
                if model.busy || model.updating { ProgressView().controlSize(.small) }
                Label(model.busy ? "Processing…" : "Live",systemImage:"circle.fill").font(.system(size:10,weight:.medium)).foregroundStyle(orange)
                Button("Save \(model.files.urls.count == 1 ? "file" : "\(model.files.urls.count) files")") { model.player?.pause(); export(model.options) }.buttonStyle(.borderedProminent).disabled(!model.canExport)
            }.padding(18)

        }.background(OrangeGlassBackdrop()).foregroundStyle(ink).tint(orange).preferredColorScheme(.light)
        .onDisappear { model.stop() }
    }
    @ViewBuilder var canvas:some View {
        if let image = (model.showOriginal ? model.image : model.renderedImage ?? model.image) {
            GeometryReader { geo in
                let size = image.size; let factor = min(geo.size.width/max(1,size.width),geo.size.height/max(1,size.height)); let w = size.width*factor,h = size.height*factor
                ZStack {
                    TransparencyGrid()
                    Image(nsImage:image).resizable().aspectRatio(contentMode:.fit)
                    if !model.showOriginal {
                        if model.isCrop { CropOverlay(selection:model.cropRect,pixelSize:model.pixelSize,changed:{ model.setCrop($0) }) }
                        else { drawingLayer(w:w,h:h) }
                    }
                }.frame(width:w,height:h).position(x:geo.size.width/2,y:geo.size.height/2)
            }
        } else if let pdf = model.renderedPDF ?? model.pdf { pdfPages(pdf) }
        else if let player = model.player {
            VStack(spacing:0) {
                if model.tool == .audioToVideo { LiveVisualizer(state:model.audioState,spectrum:model.options.visualizer == "Spectrum").frame(minHeight:200,maxHeight:.infinity) }
                else if let waveform = model.waveform { Image(nsImage:waveform).resizable().aspectRatio(contentMode:.fit).padding(20) }
                ZStack {
                    PlayerView(player:player,audioOnly:model.files.category == .audio).frame(maxHeight:model.files.category == .audio ? 60 : .infinity)
                    if isDrawing || model.isCrop { GeometryReader { g in
                        let f = min(g.size.width/model.pixelSize.width,g.size.height/model.pixelSize.height)
                        Group {
                            if model.isCrop { CropOverlay(selection:model.cropRect,pixelSize:model.pixelSize,changed:{ model.setCrop($0) }) }
                            else { drawingLayer(w:model.pixelSize.width*f,h:model.pixelSize.height*f) }
                        }.frame(width:model.pixelSize.width*f,height:model.pixelSize.height*f).position(x:g.size.width/2,y:g.size.height/2)
                    } }
                }
            }
        } else { VStack(spacing:12) { Image(nsImage:NSWorkspace.shared.icon(forFile:model.files.urls[0].path)).resizable().frame(width:90,height:90); Text(model.files.label).font(.caption) } }
    }
    @ViewBuilder func drawingLayer(w:CGFloat,h:CGFloat)->some View {
        if isDrawing {
            ZStack {
                ForEach(Array(model.options.rectangles.enumerated()),id:\.offset) { i,r in
                    let rect = CGRect(x:r.minX*w,y:r.minY*h,width:r.width*w,height:r.height*h)
                    Rectangle().strokeBorder(orange.opacity(0.7),lineWidth:1).frame(width:rect.width,height:rect.height).position(x:rect.midX,y:rect.midY)
                }
                if let drawing { Rectangle().strokeBorder(orange,style:StrokeStyle(lineWidth:2,dash:[5])).background(orange.opacity(0.1)).frame(width:drawing.width*w,height:drawing.height*h).position(x:drawing.midX*w,y:drawing.midY*h) }
                Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:3).onChanged { value in drawing = normalized(value,w:w,h:h); model.setDraft(drawing) }.onEnded { value in if let r = normalized(value,w:w,h:h),r.width > 0.005,r.height > 0.005 { model.addRectangle(r) }; drawing = nil; model.setDraft(nil) })
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
                    let _ = page.rotation += Int(model.options.rotation)+(model.options.pageRotations[i] ?? 0)
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
            HStack {
                Button { model.togglePlayback() } label: { Image(systemName:model.isPlaying ? "pause.fill" : "play.fill") }.help("Play the edited selection")
                Text(model.playbackTime,format:.number.precision(.fractionLength(2))).monospacedDigit().frame(width:55)
                Spacer()
                Text("START").font(.system(size:9,weight:.bold)).tracking(1)
                LiveNumberField(title:"Start",value:$model.options.start).frame(width:70)
                Text("END").font(.system(size:9,weight:.bold)).tracking(1)
                LiveNumberField(title:"End",value:$model.options.end).frame(width:70)
                Text("seconds").font(.system(size:10)).foregroundStyle(.secondary)
            }
            if model.duration > 0 {
                Slider(value:$model.options.start,in:0...model.duration).onChange(of:model.options.start) { v in model.player?.seek(to:CMTime(seconds:v,preferredTimescale:600)) }
                Slider(value:$model.options.end,in:0...model.duration).onChange(of:model.options.end) { end in if model.files.category == .video { model.seek(max(model.options.start,end-1.0/30)) } }
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
            if model.files.category == .pdf { note("Lower quality reduces page resolution. The saved copy is rasterized, so text selection and search are lost.") }
        case .metadata:
            Toggle("Remove all metadata",isOn:$model.options.removeMetadata)
            if model.files.category == .pdf && model.options.removeMetadata { note("Rewrites the PDF and flattens annotations to remove embedded metadata. The original stays unchanged.") }
            if !model.options.removeMetadata { TextField("Author",text:$model.options.author); TextField("Title",text:$model.options.title)
                ForEach(["Make","Model","LensModel","Artist","Copyright","GPSLatitude","GPSLatitudeRef","GPSLongitude","GPSLongitudeRef","Software","Description"],id:\.self) { key in
                    TextField(key,text:Binding(get:{ model.options.metadataTags[key] ?? "" },set:{ model.options.metadataTags[key] = $0 }))
                } }
            Text("SAVED METADATA").font(.system(size:9,weight:.bold)).foregroundStyle(.secondary)
            Text(model.effectiveMetadata)
            Text("ORIGINAL METADATA").font(.system(size:9,weight:.bold)).foregroundStyle(.secondary)
            Text(model.metadata.isEmpty ? "Reading…" : model.metadata).font(.system(size:9,design:.monospaced)).textSelection(.enabled)
        case .editImage:
            Toggle("Remove background",isOn:$model.options.removeBackground)
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
            Toggle("Remove background",isOn:$model.options.removeBackground)
            TextField("Background hex",text:$model.options.background)
            Toggle("Gradient",isOn:$model.options.gradient)
            if model.options.gradient { TextField("Second color hex",text:$model.options.secondaryBackground) }
            Picker("Canvas",selection:$model.options.aspect) { ForEach(["Original","Square","Landscape","Portrait","4:3"],id:\.self) { Text($0) } }
            integer("Padding",value:$model.options.padding); slider("Corner radius",value:$model.options.radius,range:0...200)
            Button("Use an image background…") { let p = NSOpenPanel(); p.allowedContentTypes = [.image]; if p.runModal() == .OK { model.options.backgroundImage = p.url!.path } }
        case .cropImage,.cropVideo:
            Text("\(Int(model.cropPixels.width)) × \(Int(model.cropPixels.height)) px").font(.system(size:22,weight:.medium,design:.rounded)).monospacedDigit()
            dimensions; integer("Left (pixels)",value:$model.options.cropX); integer("Top (pixels)",value:$model.options.cropY)
            Button("Reset crop") { model.resetCrop() }
            note("Drag any border or corner to resize. Drag inside to move. Arrow keys nudge by 1 px; hold Shift for 10 px.")
        case .removeBackground:
            Label(model.backgroundReady ? "Background removed" : "Finding the subject…",systemImage:model.backgroundReady ? "checkmark.circle.fill" : "person.crop.rectangle").foregroundStyle(orange)
            note("Finds foreground people and objects on your Mac. The checkerboard shows transparency. Saves a full-resolution PNG with no background.")
            if !model.backgroundError.isEmpty { Button("Try again") { model.removeBackground(retry:true) } }
        case .normalizeAudio: note("Adjusts loudness toward −16 LUFS while keeping peaks below −1.5 dB. Playback and the saved file use the same gain.")
        case .audioChannels:
            Picker("Output",selection:$model.options.channels) { Text("Mono").tag(1); Text("Stereo").tag(2) }; slider("Gain (dB)",value:$model.options.gain,range:-24...12)
        case .trimAudio,.trimVideo: note("Set the start and end below the player. The original file is preserved.")
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
        if model.backgroundEnabled && !model.backgroundError.isEmpty && model.tool != .removeBackground { Button("Try background removal again") { model.removeBackground(retry:true) } }
        Divider()
        Text("SAVE TO").font(.system(size:9,weight:.bold)).tracking(1).foregroundStyle(.secondary)
        Text(model.options.destination?.path ?? "Beside the original").font(.system(size:10)).foregroundStyle(.secondary).lineLimit(3).truncationMode(.middle)
        Button("Choose folder…") { let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; if p.runModal() == .OK { model.options.destination = p.url } }
    }
    var dimensions:some View { VStack(alignment:.leading,spacing:12) { integer("Width (pixels)",value:$model.options.width); integer("Height (pixels)",value:$model.options.height) } }
    var rotation:some View { Picker("Rotation",selection:$model.options.rotation) { Text("0°").tag(0.0); Text("90°").tag(90.0); Text("180°").tag(180.0); Text("270°").tag(270.0) } }
    func integer(_ title:String,value:Binding<Int>)->some View { VStack(alignment:.leading,spacing:5) { Text(title).font(.system(size:11)); LiveNumberField(title:title,value:Binding(get:{ Double(value.wrappedValue) },set:{ value.wrappedValue = Int($0) }),integer:true) } }
    func number(_ title:String,value:Binding<Double>)->some View { VStack(alignment:.leading,spacing:5) { Text(title).font(.system(size:11)); LiveNumberField(title:title,value:value) } }
    func slider(_ title:String,value:Binding<Double>,range:ClosedRange<Double>)->some View { VStack(alignment:.leading,spacing:8) { HStack { Text(title); Spacer(); Text(value.wrappedValue,format:.number.precision(.fractionLength(1))).foregroundStyle(.secondary).monospacedDigit() }; Slider(value:value,in:range) }.font(.system(size:11)) }
    func note(_ text:String)->some View { Text(text).font(.system(size:11)).foregroundStyle(.secondary).lineSpacing(4) }
}

struct TransparencyGrid:View {
    var body:some View {
        Canvas { context,size in
            context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(Color(red:1,green:0.98,blue:0.94)))
            let side:CGFloat = 14
            for y in 0..<Int(ceil(size.height/side)) {
                for x in 0..<Int(ceil(size.width/side)) where (x+y)%2 == 0 {
                    context.fill(Path(CGRect(x:CGFloat(x)*side,y:CGFloat(y)*side,width:side,height:side)),with:.color(Color(red:0.9,green:0.86,blue:0.8)))
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Numeric edits reach the model while typing, rather than waiting for Return.
struct LiveNumberField:View {
    var title:String
    @Binding var value:Double
    var integer = false
    @State private var text = ""
    var body:some View {
        TextField(title,text:$text).textFieldStyle(.roundedBorder)
            .onAppear { text = formatted(value) }
            .onChange(of:text) { input in
                if let number = Double(input),number.isFinite,abs(number) < 1_000_000_000 { value = integer ? number.rounded(.towardZero) : number }
            }
            .onChange(of:value) { number in if Double(text) != number { text = formatted(number) } }
            .onSubmit { text = formatted(value) }
    }
    private func formatted(_ number:Double) -> String { integer ? String(Int(number)) : String(format:"%.3f",number).replacingOccurrences(of:"\\.?0+$",with:"",options:.regularExpression) }
}
