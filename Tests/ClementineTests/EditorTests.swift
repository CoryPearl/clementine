import XCTest
import AppKit
import AVFoundation
import PDFKit
import CoreImage
@testable import Clementine

final class EditorTests:XCTestCase {
    var root:URL!
    var engine:Engine!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("clementine-editor-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        engine = Engine(token:CancellationToken())
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at:root) }
    func image() throws -> URL {
        let context = CGContext(data:nil,width:200,height:120,bitsPerComponent:8,bytesPerRow:0,space:ImageRendering.colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red:0.25,green:0.4,blue:0.65,alpha:1));context.fill(CGRect(x:0,y:0,width:200,height:120))
        context.setFillColor(CGColor(red:0.8,green:0.25,blue:0.2,alpha:1));context.fill(CGRect(x:100,y:0,width:100,height:120))
        let url = root.appendingPathComponent("source.png");try engine.writeCGImage(context.makeImage()!,to:url);return url
    }
    @MainActor func waitUntil(_ message:String,timeout:Double = 8,_ condition:@escaping ()->Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { try await Task.sleep(nanoseconds:10_000_000) }
        XCTAssertTrue(condition(),message)
    }
    func cg(_ image:NSImage) -> CGImage { image.cgImage(forProposedRect:nil,context:nil,hints:nil)! }
    func color(_ image:CGImage,x:Int,y:Int) -> NSColor { NSBitmapImageRep(cgImage:image).colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)! }
    func testCropHandlesKeepOppositeEdgesFixedAndStayInsideImage() {
        let rect = CGRect(x:0.2,y:0.25,width:0.5,height:0.5),minimum = CGSize(width:0.01,height:0.01)
        let topLeft = CropGeometry.dragged(rect,handle:.topLeft,translation:CGSize(width:-1,height:-1),minimum:minimum)
        XCTAssertEqual(topLeft.minX,0);XCTAssertEqual(topLeft.minY,0)
        XCTAssertEqual(topLeft.maxX,rect.maxX,accuracy:0.0001);XCTAssertEqual(topLeft.maxY,rect.maxY,accuracy:0.0001)
        let collapsed = CropGeometry.dragged(rect,handle:.left,translation:CGSize(width:2,height:0),minimum:minimum)
        XCTAssertEqual(collapsed.width,0.01,accuracy:0.0001);XCTAssertEqual(collapsed.maxX,rect.maxX,accuracy:0.0001)
        let moved = CropGeometry.dragged(rect,handle:.move,translation:CGSize(width:2,height:-2),minimum:minimum)
        XCTAssertEqual(moved.maxX,1);XCTAssertEqual(moved.minY,0);XCTAssertEqual(moved.size,rect.size)
        for handle in CropHandle.allCases {
            let result = CropGeometry.dragged(rect,handle:handle,translation:CGSize(width:0.15,height:-0.13),minimum:minimum)
            XCTAssertGreaterThanOrEqual(result.minX,0);XCTAssertGreaterThanOrEqual(result.minY,0)
            XCTAssertLessThanOrEqual(result.maxX,1);XCTAssertLessThanOrEqual(result.maxY,1)
        }
    }
    @MainActor func testNativeCropBorderDragPublishesContinuously() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect:CGRect(x:-10000,y:-10000,width:400,height:300),styleMask:.borderless,backing:.buffered,defer:false)
        let view = CropSelectionView(frame:CGRect(x:0,y:0,width:400,height:300));window.contentView = view
        view.pixelSize = CGSize(width:800,height:600)
        view.selection = CGRect(x:0.2,y:0.2,width:0.6,height:0.6)
        var changes:[CGRect] = [];view.changed = { changes.append($0) }
        func event(_ type:NSEvent.EventType,_ point:CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with:type,location:view.convert(point,to:nil),modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        }
        XCTAssertEqual(view.handle(at:CGPoint(x:80,y:100)),.left)
        view.mouseDown(with:event(.leftMouseDown,CGPoint(x:80,y:100)))
        view.mouseDragged(with:event(.leftMouseDragged,CGPoint(x:60,y:100)))
        view.mouseDragged(with:event(.leftMouseDragged,CGPoint(x:40,y:100)))
        view.mouseUp(with:event(.leftMouseUp,CGPoint(x:40,y:100)))
        XCTAssertEqual(changes.count,2)
        XCTAssertEqual(changes.last!.minX,0.1,accuracy:0.0001)
        XCTAssertEqual(changes.last!.maxX,0.8,accuracy:0.0001)
        XCTAssertEqual(view.handle(at:view.point(.bottomRight)),.bottomRight)
    }
    @MainActor func testImageControlsRenderAutomaticallyAndSavedPixelsMatch() async throws {
        let input = try image(),before = try Data(contentsOf:input)
        let model = EditorModel(operation:Tool.editImage.descriptor,files:FileSelection(urls:[input]));defer { model.stop() }
        try await waitUntil("Initial live canvas") { model.renderedImage != nil && !model.updating && !model.busy }
        let baseline = color(cg(model.renderedImage!),x:20,y:20)
        model.options.exposure = 1
        try await waitUntil("Exposure updates without a Preview command") { !model.updating }
        let exposed = color(cg(model.renderedImage!),x:20,y:20)
        XCTAssertGreaterThan(exposed.blueComponent,baseline.blueComponent+0.05)
        // Rapid updates must finish on the newest settings, with no stale render overwriting them.
        for n in 0..<16 { model.options.exposure = Double(n)/15 }
        var options = model.options;options.exposure = -0.5;options.effect = "Sepia";options.rotation = 90;options.flipHorizontal = true;model.options = options
        try await waitUntil("Latest edit finishes") { !model.updating }
        let canvas = cg(model.renderedImage!)
        options.destination = root
        let saved = try engine.execute(.init(urls:[input],operation:"tool:editImage",options:options)) { _,_ in }[0]
        let output = try ImageRendering.load(saved)
        XCTAssertEqual(canvas.width,120);XCTAssertEqual(canvas.height,200)
        XCTAssertEqual(canvas.width,output.width);XCTAssertEqual(canvas.height,output.height)
        for point in [(20,20),(70,170)] {
            let a = color(canvas,x:point.0,y:point.1),b = color(output,x:point.0,y:point.1)
            XCTAssertEqual(a.redComponent,b.redComponent,accuracy:0.01);XCTAssertEqual(a.greenComponent,b.greenComponent,accuracy:0.01);XCTAssertEqual(a.blueComponent,b.blueComponent,accuracy:0.01)
        }
        XCTAssertEqual(try Data(contentsOf:input),before)
    }
    @MainActor func testCropPixelsAndBorderShareOneSelection() async throws {
        let input = try image();let model = EditorModel(operation:Tool.cropImage.descriptor,files:FileSelection(urls:[input]));defer { model.stop() }
        try await waitUntil("Crop loads") { model.workingSource != nil && !model.busy }
        XCTAssertEqual(model.cropRect,CGRect(x:0,y:0,width:1,height:1))
        model.setCrop(CGRect(x:0.25,y:0.2,width:0.5,height:0.5))
        XCTAssertEqual(model.options.cropX,50);XCTAssertEqual(model.options.cropY,24);XCTAssertEqual(model.options.width,100);XCTAssertEqual(model.options.height,60)
        let cropped = try ImageRendering.render(try ImageRendering.load(input),tool:.cropImage,options:model.options)
        XCTAssertEqual(cropped.width,100);XCTAssertEqual(cropped.height,60)
        model.options.cropX = 190;model.options.width = 200
        XCTAssertEqual(model.cropPixels.width,10)
        let clamped = try ImageRendering.render(try ImageRendering.load(input),tool:.cropImage,options:model.options)
        XCTAssertEqual(clamped.width,10)
        model.resetCrop();XCTAssertEqual(model.cropRect,CGRect(x:0,y:0,width:1,height:1))
    }
    @MainActor func testAnnotationAndBlurRedactionUpdateLive() async throws {
        let input = try image()
        let model = EditorModel(operation:Tool.redactImage.descriptor,files:FileSelection(urls:[input]));defer { model.stop() }
        try await waitUntil("Image loads") { model.renderedImage != nil && !model.updating }
        model.setDraft(CGRect(x:0,y:0,width:0.3,height:0.4))
        try await waitUntil("A drag changes actual pixels before mouse-up") { !model.updating }
        XCTAssertLessThan(color(cg(model.renderedImage!),x:10,y:10).redComponent,0.01)
        model.setDraft(nil)
        try await waitUntil("Canceled draft restores the source") { !model.updating }
        XCTAssertGreaterThan(color(cg(model.renderedImage!),x:10,y:10).blueComponent,0.5)
        model.addRectangle(CGRect(x:0.35,y:0.1,width:0.3,height:0.8));model.options.blur = true
        try await waitUntil("Blur is rendered live") { !model.updating }
        XCTAssertGreaterThan(color(cg(model.renderedImage!),x:100,y:30).redComponent,0.05)
    }
    func testVideoRedactionTracksTheCurrentFrameAndTimeRange() throws {
        let source = CIImage(color:.white).cropped(to:CGRect(x:0,y:0,width:100,height:80))
        var o = OperationOptions();o.rectangles = [CGRect(x:0,y:0,width:0.5,height:0.5)];o.redactRanges = "1-2"
        let before = try ImageRendering.cgImage(LiveVideoRendering.frame(source,tool:.redactVideo,options:o,time:0.5))
        let during = try ImageRendering.cgImage(LiveVideoRendering.frame(source,tool:.redactVideo,options:o,time:1.5))
        XCTAssertGreaterThan(color(before,x:10,y:10).redComponent,0.95)
        XCTAssertLessThan(color(during,x:10,y:10).redComponent,0.01)
        XCTAssertGreaterThan(color(during,x:80,y:60).redComponent,0.95)
    }
    func testLiveAudioGainChannelsAndBleepRespectSamples() {
        let state = LiveAudioState();state.floatPCM = true;state.sampleRate = 48000
        var o = OperationOptions();o.channels = 1;o.gain = 20*log10(2)
        state.update(tool:.audioChannels,options:o,duration:5)
        func process(_ start:Double) -> [Float] {
            var samples = (0..<64).flatMap { _ in [Float(0.4),Float(-0.2)] }
            samples.withUnsafeMutableBufferPointer { pointer in
                var buffers = AudioBufferList(mNumberBuffers:1,mBuffers:AudioBuffer(mNumberChannels:2,mDataByteSize:UInt32(pointer.count*MemoryLayout<Float>.size),mData:pointer.baseAddress))
                state.apply(&buffers,frames:64,start:start)
            }
            return samples
        }
        let mono = process(0)
        XCTAssertEqual(mono[0],0.2,accuracy:0.00001);XCTAssertEqual(mono[1],0.2,accuracy:0.00001)
        o.redactRanges = "1-2";state.update(tool:.redactAudio,options:o,duration:5)
        let clean = process(0.2),bleep = process(1.1)
        XCTAssertEqual(clean[0],0.4);XCTAssertEqual(clean[1],-0.2)
        XCTAssertLessThan(bleep.map { abs($0) }.max()!,0.019)
        XCTAssertGreaterThan(bleep.map { abs($0) }.max()!,0.01)
    }
    @MainActor func testMediaEditingKeepsFullDurationAndAppliesRateAndTrimImmediately() async throws {
        if !FileManager.default.isExecutableFile(atPath:Engine.toolsRoot.appendingPathComponent("ffmpeg").path) { throw XCTSkip("Needs the packaged media engines") }
        let video = root.appendingPathComponent("twelve-seconds.mp4")
        try engine.ff(["-f","lavfi","-i","testsrc=size=64x48:rate=2","-t","12","-c:v","libx264","-pix_fmt","yuv420p",video.path])
        let model = EditorModel(operation:Tool.changeVideoSpeed.descriptor,files:FileSelection(urls:[video]));defer { model.stop() }
        try await waitUntil("Native player loads",timeout:12) { model.player != nil && !model.busy }
        XCTAssertEqual(model.duration,12,accuracy:0.01);XCTAssertEqual(model.options.end,12,accuracy:0.01)
        var o = model.options;o.speed = 2;o.start = 1;o.end = 11;model.options = o
        XCTAssertEqual(model.player!.defaultRate,2)
        XCTAssertEqual(model.player!.currentItem!.forwardPlaybackEndTime.seconds,11,accuracy:0.01)
        XCTAssertEqual(model.player!.currentItem!.reversePlaybackEndTime.seconds,1,accuracy:0.01)
        XCTAssertNil(model.validationMessage)
        model.options.end = 0.5;XCTAssertNotNil(model.validationMessage);XCTAssertFalse(model.canExport)
    }
    @MainActor func testBackgroundRemovalProducesTransparentPNGAndCachesTheCutout() async throws {
        guard let fixture = ProcessInfo.processInfo.environment["CLEMENTINE_SUBJECT_FIXTURE"] else { throw XCTSkip("Set CLEMENTINE_SUBJECT_FIXTURE to a real subject photo for the Vision integration test") }
        let input = URL(fileURLWithPath:fixture);let before = try Data(contentsOf:input)
        let model = EditorModel(operation:Tool.editImage.descriptor,files:FileSelection(urls:[input]));defer { model.stop() }
        try await waitUntil("Photo loads") { model.renderedImage != nil && !model.updating }
        model.options.removeBackground = true
        try await waitUntil("Vision removes the background",timeout:20) { model.backgroundReady || !model.backgroundError.isEmpty }
        XCTAssertTrue(model.backgroundReady,model.backgroundError)
        try await waitUntil("Cutout appears") { !model.updating && !model.busy }
        var o = model.options;o.destination = root
        let output = try engine.execute(.init(urls:[input],operation:"tool:editImage",options:o)) { _,_ in }[0]
        XCTAssertEqual(output.pathExtension,"png")
        let result = try ImageRendering.load(output)
        let a = color(result,x:0,y:0),subject = color(result,x:result.width/2,y:result.height/2)
        XCTAssertLessThan(a.alphaComponent,0.01);XCTAssertGreaterThan(subject.alphaComponent,0.9)
        model.options.removeBackground = false
        try await waitUntil("Original background returns") { !model.updating }
        XCTAssertGreaterThan(color(cg(model.renderedImage!),x:0,y:0).alphaComponent,0.99)
        model.options.removeBackground = true
        XCTAssertTrue(model.backgroundReady);XCTAssertFalse(model.busy)
        XCTAssertEqual(try Data(contentsOf:input),before)
    }
    @MainActor func testPDFCompressionRefreshesAutomatically() async throws {
        let photo = try image(),input = root.appendingPathComponent("document.pdf")
        try engine.imagesPDF([photo,photo],to:input)
        let model = EditorModel(operation:Tool.compress.descriptor,files:FileSelection(urls:[input]));defer { model.stop() }
        try await waitUntil("Encoded PDF appears without a Preview command") { model.renderedPDF != nil && !model.updating }
        XCTAssertEqual(model.renderedPDF?.pageCount,2)
        let firstSize = model.renderedPDF!.page(at:0)!.bounds(for:.mediaBox).size
        model.options.quality = 15
        try await waitUntil("Quality updates the actual PDF pages") { !model.updating }
        let nextSize = model.renderedPDF!.page(at:0)!.bounds(for:.mediaBox).size
        XCTAssertLessThan(nextSize.width,firstSize.width)
        XCTAssertTrue(model.message.contains("Encoded size:"))
        XCTAssertEqual(PDFDocument(url:input)?.pageCount,2)
    }
    @MainActor func testNativeAudioItemConnectsTheLiveProcessor() async throws {
        if !FileManager.default.isExecutableFile(atPath:Engine.toolsRoot.appendingPathComponent("ffmpeg").path) { throw XCTSkip("Needs the packaged audio engines") }
        let input = root.appendingPathComponent("tone.wav")
        try engine.ff(["-f","lavfi","-i","sine=frequency=440:sample_rate=48000","-t","1.5","-ac","2",input.path])
        let model = EditorModel(operation:Tool.audioChannels.descriptor,files:FileSelection(urls:[input]));defer { model.stop() }
        try await waitUntil("Audio player loads with its tap") { model.player != nil && !model.busy }
        XCTAssertNotNil(model.player?.currentItem?.audioMix?.inputParameters.first?.audioTapProcessor)
        var o = model.options;o.channels = 1;o.gain = 6;model.options = o
        XCTAssertNotNil(model.player?.currentItem?.audioMix?.inputParameters.first?.audioTapProcessor)
        XCTAssertEqual(model.options.end,1.5,accuracy:0.01)
        // Keep playback paused: the test must not play a tone through the user's speakers.
        XCTAssertEqual(model.player?.rate,0)
    }
}
