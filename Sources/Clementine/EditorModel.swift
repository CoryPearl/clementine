import AppKit
import SwiftUI
import AVFoundation
import PDFKit
import CoreImage

@MainActor final class EditorModel:ObservableObject {
    let operation:OperationDescriptor;let files:FileSelection;let tool:Tool
    @Published var options = OperationOptions() { didSet { if ready && options != oldValue { settingsChanged() } } }
    @Published var image:NSImage?;@Published var renderedImage:NSImage?;@Published var waveform:NSImage?
    @Published var player:AVPlayer?;@Published var pdf:PDFDocument?;@Published var renderedPDF:PDFDocument?
    @Published var pixelSize = CGSize(width:16,height:9)
    @Published var duration = 0.0
    @Published var message = ""
    @Published var metadata = ""
    @Published var busy = false
    @Published var updating = false
    @Published var backgroundError = ""
    @Published var backgroundReady = false
    @Published var playbackTime = 0.0
    @Published var isPlaying = false
    @Published var showOriginal = false
    @Published var page = 0
    let audioState = LiveAudioState();let videoState = LiveVideoState()
    private(set) var workingSource:CGImage?
    private var cutout:CGImage?,draft:CGRect?,ready = false,closed = false,backgroundAttempted = false
    private var renderRevision = 0,completedRevision = 0
    private var renderWorker:Task<Void,Never>?,compressionTask:Task<Void,Never>?,backgroundTask:Task<Void,Never>?
    private var compressionToken:CancellationToken?
    private var observedPlayer:AVPlayer?
    private var timeObserver:Any?,normalizationGain = 1.0,lastVideoOptions:OperationOptions?
    private var videoComposition:AVMutableVideoComposition?
    private let loadToken = CancellationToken(),metadataToken = CancellationToken()
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Clementine-editor-\(UUID().uuidString)")
    var backgroundEnabled:Bool { tool == .removeBackground || options.removeBackground }
    var isCrop:Bool { [.cropImage,.cropVideo].contains(tool) }
    var cropRect:CGRect { CropGeometry.normalized(options:options,size:pixelSize) }
    var cropPixels:CGRect { CropGeometry.pixelRect(options:options,size:pixelSize) }
    var validationMessage:String? {
        if options.width < 0 || options.height < 0 || options.width > 30000 || options.height > 30000 { return "Image and video dimensions must be between 0 and 30,000 pixels." }
        if options.width > 0 && options.height > 0 && Int64(options.width)*Int64(options.height) > 150_000_000 { return "Choose dimensions totaling no more than 150 megapixels." }
        if let pdf,[Tool.splitPDF,.organizePDF].contains(tool) {
            do { _ = try Engine(token:CancellationToken()).pageIndices(options.pageOrder,count:pdf.pageCount) }
            catch { return error.localizedDescription }
        }
        if [.audio,.video].contains(files.category),duration > 0 {
            if !options.start.isFinite || !options.end.isFinite || options.start < 0 || options.end <= options.start || options.end > duration+0.05 { return "Choose an end time after Start and within the file’s duration." }
            if tool == .redactAudio || tool == .redactVideo {
                do { _ = try Engine(token:CancellationToken()).parseRanges(options.redactRanges,duration:duration) }
                catch { return error.localizedDescription }
            }
        }
        return nil
    }
    var canExport:Bool {
        if [.redactImage,.redactVideo].contains(tool) && options.rectangles.isEmpty { return false }
        if tool == .redactAudio && options.redactRanges.trimmingCharacters(in:.whitespaces).isEmpty { return false }
        return !busy && validationMessage == nil && (!backgroundEnabled || backgroundReady)
    }
    var effectiveMetadata:String {
        if options.removeMetadata { return "Metadata will be removed from the saved copy." }
        var entries = options.metadataTags.filter { !$0.value.isEmpty }
        if !options.author.isEmpty { entries["Author"] = options.author }
        if !options.title.isEmpty { entries["Title"] = options.title }
        return entries.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator:"\n")
    }

    init(operation:OperationDescriptor,files:FileSelection) {
        self.operation = operation;self.files = files;tool = Tool(rawValue:String(operation.id.dropFirst(5)))!
        options.quality = UserDefaults.standard.double(forKey:"quality");if options.quality <= 0 { options.quality = 82 }
        if let path = UserDefaults.standard.string(forKey:"outputFolder"),!path.isEmpty { options.destination = URL(fileURLWithPath:path) }
        if tool == .removeBackground { options.removeBackground = true }
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let input = files.urls[0]
        if files.category == .pdf { pdf = PDFDocument(url:input) }
        ready = true
        loadInfo()
    }
    deinit {
        compressionToken?.cancel();renderWorker?.cancel();compressionTask?.cancel();backgroundTask?.cancel()
        loadToken.cancel();metadataToken.cancel()
        if let timeObserver { observedPlayer?.removeTimeObserver(timeObserver) }
        try? FileManager.default.removeItem(at:directory)
    }
    func stop() {
        closed = true;player?.pause();compressionToken?.cancel();compressionTask?.cancel();backgroundTask?.cancel();renderWorker?.cancel()
        loadToken.cancel();metadataToken.cancel()
        if let timeObserver { player?.removeTimeObserver(timeObserver);self.timeObserver = nil }
    }
    private func loadInfo() {
        let input = files.urls[0],category = files.category,tool = tool,directory = directory,loadToken = loadToken
        if category == .image {
            busy = true
            Task { [weak self] in
                do {
                    let result = try await Task.detached { () -> (CGImage,CGSize) in
                        let engine = Engine(token:loadToken)
                        if let size = ImageRendering.dimensions(input) { return (try engine.loadEditableImage(input,maximumDimension:1600),size) }
                        let full = try engine.loadEditableImage(input)
                        return (try ImageRendering.resized(full,maximumDimension:1600),CGSize(width:full.width,height:full.height))
                    }.value
                    guard let self,!closed else { return }
                    workingSource = result.0;pixelSize = result.1;image = NSImage(cgImage:result.0,size:.zero)
                    if isCrop { var o = options;o.width = Int(pixelSize.width);o.height = Int(pixelSize.height);options = o }
                    else if tool == .compress { var o = options;o.width = Int(pixelSize.width);o.height = Int(pixelSize.height);options = o }
                    busy = false;settingsChanged()
                } catch { self?.busy = false;self?.message = error.localizedDescription }
            }
        }
        if [.audio,.video].contains(category) {
            busy = true
            Task { [weak self] in
                do {
                    let result = try await Task.detached { () async throws -> (URL,Double,CGSize,Data?,Double) in
                        let engine = Engine(token:loadToken)
                        let originalAsset = AVURLAsset(url:input)
                        var playable = input
                        if try await !originalAsset.load(.isPlayable) {
                            playable = directory.appendingPathComponent(category == .audio ? "playback.wav" : "playback.mp4")
                            try engine.media(input,to:playable,options:OperationOptions())
                        }
                        let asset = AVURLAsset(url:playable)
                        let track = try await asset.loadTracks(withMediaType:.video).first
                        var transformed = CGSize(width:16,height:9)
                        if let track { let (size,transform) = try await track.load(.naturalSize,.preferredTransform);transformed = size.applying(transform) }
                        let size = CGSize(width:abs(transformed.width),height:abs(transformed.height))
                        var wave:Data?
                        if category == .audio {
                            let file = directory.appendingPathComponent("waveform.png")
                            try? engine.ff(["-i",input.path,"-filter_complex","showwavespic=s=1000x180:colors=0xf56d29","-frames:v","1",file.path]);wave = try? Data(contentsOf:file)
                        }
                        let gain = tool == .normalizeAudio ? (try engine.normalizationGain(input)) : 1
                        let seconds = try await asset.load(.duration).seconds
                        return (playable,seconds.isFinite ? seconds : engine.duration(input),size,wave,gain)
                    }.value
                    guard let self,!closed else { return }
                    duration = result.1;pixelSize = result.2;waveform = result.3.flatMap { NSImage(data:$0) };normalizationGain = result.4
                    var o = options;o.end = duration
                    if isCrop { o.width = Int(pixelSize.width);o.height = Int(pixelSize.height) }
                    options = o
                    let asset = AVURLAsset(url:result.0),item = AVPlayerItem(asset:asset)
                    item.audioTimePitchAlgorithm = .timeDomain
                    if let track = try await asset.loadTracks(withMediaType:.audio).first { item.audioMix = try audioState.makeMix(track:track) }
                    if category == .video && tool != .cropVideo {
                        let state = videoState
                        let composition = AVVideoComposition(asset:asset,applyingCIFiltersWithHandler:{ request in
                            let frame = LiveVideoRendering.frame(request.sourceImage,tool:tool,options:state.options,time:request.compositionTime.seconds)
                            request.finish(with:frame,context:ImageRendering.context)
                        }).mutableCopy() as! AVMutableVideoComposition
                        videoComposition = composition;item.videoComposition = composition
                    }
                    player = AVPlayer(playerItem:item);observedPlayer = player
                    timeObserver = player?.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.05,preferredTimescale:600),queue:.main) { [weak self] time in
                        Task { @MainActor [weak self] in
                            guard let self,!closed else { return };playbackTime = time.seconds.isFinite ? time.seconds : 0;isPlaying = player?.rate != 0
                        }
                    }
                    busy = false;message = "";settingsChanged()
                } catch { self?.busy = false;self?.message = error.localizedDescription }
            }
        }
        if tool == .metadata {
            let token = metadataToken
            Task { [weak self] in
                let text = await Task.detached { let engine = Engine(token:token);return (try? engine.run(engine.tool("exiftool"),["-G","-s",input.path])) ?? "" }.value
                guard let self,!closed else { return };metadata = text
            }
        }
        if category == .pdf && tool == .compress { scheduleCompression() }
    }
    func settingsChanged() {
        guard !closed else { return }
        updateMedia()
        if files.category == .image {
            if backgroundEnabled && !backgroundReady { removeBackground() }
            if tool == .compress { scheduleCompression() } else { scheduleImageRender() }
        }
        if files.category == .pdf && tool == .compress { scheduleCompression() }
        if tool == .videoSnapshots,let first = options.splitTimes.split(separator:",").first,let time = Double(first.trimmingCharacters(in:.whitespaces)),time >= 0,time < duration { seek(time) }
    }
    func removeBackground(retry:Bool = false) {
        guard workingSource != nil else { return }
        if retry { backgroundAttempted = false;backgroundError = "" }
        guard !backgroundAttempted else { return }
        backgroundAttempted = true;busy = true;backgroundError = "";let input = files.urls[0]
        backgroundTask = Task { [weak self] in
            do {
                let result = try await Task.detached { () -> CGImage in
                    let full = try Engine(token:CancellationToken()).loadEditableImage(input)
                    return try ImageRendering.resized(ImageRendering.removeBackground(full),maximumDimension:1600)
                }.value
                guard let self,!closed,!Task.isCancelled else { return }
                cutout = result;backgroundReady = true;busy = false;scheduleImageRender()
            } catch {
                guard let self,!closed else { return };busy = false;backgroundError = error.localizedDescription
            }
        }
    }
    private func scheduleImageRender() {
        renderRevision &+= 1
        guard renderWorker == nil,workingSource != nil else { return }
        updating = true
        renderWorker = Task { [weak self] in
            guard let self else { return }
            // A serial worker coalesces pending edits and still delivers frames during a slider drag.
            while !closed && !Task.isCancelled && completedRevision < renderRevision {
                let revision = renderRevision
                guard let source = (backgroundEnabled ? cutout : nil) ?? workingSource else { break }
                var o = ImageRendering.workingOptions(options,sourceSize:pixelSize,workingSize:CGSize(width:source.width,height:source.height))
                if let draft { o.rectangles.append(draft) }
                let tool = tool
                do {
                    let settings = o
                    let output = try await Task.detached { try ImageRendering.render(source,tool:tool == .cropImage ? .metadata : tool,options:settings) }.value
                    guard !closed,!Task.isCancelled else { break }
                    renderedImage = NSImage(cgImage:output,size:.zero)
                    if revision == renderRevision { message = "" }
                } catch { if revision == renderRevision { message = error.localizedDescription } }
                completedRevision = revision
            }
            updating = false;renderWorker = nil
        }
    }
    private func scheduleCompression() {
        compressionTask?.cancel();compressionToken?.cancel()
        let token = CancellationToken();compressionToken = token
        let input = files.urls[0],o = options,base = directory,isPDF = files.category == .pdf
        updating = true
        compressionTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds:120_000_000)
                let result = try await Task.detached { () -> (CGImage?,Data?,Int64) in
                    let work = base.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true)
                    defer { try? FileManager.default.removeItem(at:work) }
                    let engine = Engine(token:token)
                    let output = try engine.perform(.compress,input:input,all:[input],options:o,work:work)[0]
                    if isPDF { return (nil,try Data(contentsOf:output),engine.fileSize(output)) }
                    return (try engine.loadEditableImage(output,maximumDimension:1600),nil,engine.fileSize(output))
                }.value
                guard let self,!closed,!Task.isCancelled,!token.cancelled else { return }
                if let image = result.0 { renderedImage = NSImage(cgImage:image,size:.zero) }
                if let data = result.1 { renderedPDF = PDFDocument(data:data) }
                message = "Encoded size: \(ByteCountFormatter.string(fromByteCount:result.2,countStyle:.file))";updating = false
            } catch {
                guard let self,!closed,!Task.isCancelled,!token.cancelled else { return };message = error.localizedDescription;updating = false
            }
        }
    }
    private func updateMedia() {
        guard let player,let item = player.currentItem else { return }
        audioState.update(tool:tool,options:options,normalizationGain:normalizationGain,duration:duration)
        var displayed = options;if let draft { displayed.rectangles.append(draft) }
        if validationMessage == nil { videoState.update(displayed) }
        let rate = Float(tool == .changeVideoSpeed ? min(4,max(0.25,options.speed)) : 1)
        player.defaultRate = rate;if player.rate != 0 { player.rate = rate }
        if validationMessage == nil {
            item.forwardPlaybackEndTime = CMTime(seconds:options.end,preferredTimescale:600)
            item.reversePlaybackEndTime = CMTime(seconds:options.start,preferredTimescale:600)
        }
        if let composition = videoComposition,displayed != lastVideoOptions,validationMessage == nil {
            if tool == .compress { composition.renderSize = LiveVideoRendering.outputSize(source:pixelSize,options:options) }
            if player.rate == 0 || tool == .compress { item.videoComposition = composition.copy() as? AVVideoComposition }
            lastVideoOptions = displayed
        }
    }
    func togglePlayback() {
        guard let player else { return }
        if player.rate != 0 { player.pause();isPlaying = false;return }
        if playbackTime < options.start || playbackTime >= options.end-0.03 { player.seek(to:CMTime(seconds:options.start,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero) }
        player.play();isPlaying = true
    }
    func seek(_ seconds:Double) { player?.seek(to:CMTime(seconds:seconds,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero) }
    func setCrop(_ rect:CGRect) {
        let r = CropGeometry.clamped(rect,minimum:CGSize(width:1/max(1,pixelSize.width),height:1/max(1,pixelSize.height)))
        var o = options
        o.cropX = Int((r.minX*pixelSize.width).rounded());o.cropY = Int((r.minY*pixelSize.height).rounded())
        o.width = max(1,Int((r.maxX*pixelSize.width).rounded())-o.cropX);o.height = max(1,Int((r.maxY*pixelSize.height).rounded())-o.cropY)
        options = o
    }
    func resetCrop() { setCrop(CGRect(x:0,y:0,width:1,height:1)) }
    func setDraft(_ rect:CGRect?) { draft = rect;if files.category == .image { scheduleImageRender() } else { updateMedia() } }
    func addRectangle(_ rect:CGRect) { draft = nil;options.rectangles.append(rect) }
    func detect(faces:Bool) {
        busy = true;let input = files.urls[0]
        Task { [weak self] in
            do {
                let result = try await Task.detached { try Engine(token:CancellationToken()).detectRegions(input,faces:faces) }.value
                guard let self,!closed else { return };options.rectangles.append(contentsOf:result);message = "Found \(result.count) areas. Review before saving.";busy = false
            } catch { self?.message = error.localizedDescription;self?.busy = false }
        }
    }
    func qr() {
        let input = files.urls[0]
        Task { [weak self] in
            do { let text = try await Task.detached { try Engine(token:CancellationToken()).readQRCode(input) }.value
                guard let self,!closed else { return };message = text;NSPasteboard.general.clearContents();NSPasteboard.general.setString(text,forType:.string)
            } catch { self?.message = error.localizedDescription }
        }
    }
}

extension Engine {
    func normalizationGain(_ input:URL) throws -> Double {
        let text = try run(try tool("ffmpeg"),["-hide_banner","-nostdin","-i",input.path,"-af","loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json","-f","null","-"],timeout:7200)
        guard let start = text.lastIndex(of:"{"),let end = text.lastIndex(of:"}"),start < end,
              let values = try JSONSerialization.jsonObject(with:Data(text[start...end].utf8)) as? [String:String],
              let integrated = Double(values["input_i"] ?? ""),let peak = Double(values["input_tp"] ?? ""),integrated.isFinite,peak.isFinite else { return 1 }
        return pow(10,min(-16-integrated,-1.5-peak)/20)
    }
}
