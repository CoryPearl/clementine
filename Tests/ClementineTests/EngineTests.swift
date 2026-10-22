import XCTest
import AppKit
import PDFKit
import CoreText
@testable import Clementine

final class EngineTests:XCTestCase {
    var root:URL!; var inputs:URL!; var output:URL!; var engine:Engine!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("clementine-tests-\(UUID().uuidString)")
        inputs = root.appendingPathComponent("inputs"); output = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at:inputs,withIntermediateDirectories:true); try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        engine = Engine(token:CancellationToken())
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at:root) }
    func fixtureImage(_ name:String = "sample.png") throws -> URL {
        let url = inputs.appendingPathComponent(name)
        let ctx = CGContext(data:nil,width:160,height:120,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red:1,green:0.5,blue:0.2,alpha:1)); ctx.fill(CGRect(x:0,y:0,width:160,height:120))
        try engine.writeCGImage(ctx.makeImage()!,to:url); return url
    }
    func fixturePDF() throws -> URL { let image = try fixtureImage(); let pdf = inputs.appendingPathComponent("pages.pdf"); try engine.imagesPDF([image,image],to:pdf); return pdf }
    func run(_ op:String,_ files:[URL],options:OperationOptions = .init()) throws -> [URL] {
        var o = options; o.destination = output
        return try engine.execute(.init(urls:files,operation:op,options:o)) { _,_ in }
    }
    func requireTools() throws { if !FileManager.default.isExecutableFile(atPath:Engine.toolsRoot.appendingPathComponent("ffmpeg").path) { throw XCTSkip("Run packaged engine tests with CLEMENTINE_TOOLS set.") } }
    func testReferenceConversionMatrixHas275Edges() {
        let inputs = Registry.images + Registry.audios + Registry.videos + ["gif","pdf","ppt","pptx","docx","pages","md","rtf","rtfd","textclipping","epub","txt"] + Registry.sheets + ["srt","vtt"] + Registry.archives
        XCTAssertEqual(inputs.reduce(0) { $0+Registry.outputs($1).count },275)
        XCTAssertEqual(Tool.allCases.count,27); XCTAssertEqual(Registry.actions.count,6)
        for input in inputs { XCTAssertFalse(Registry.outputs(input).contains(input)); XCTAssertFalse(Registry.outputs(input).contains("xls")); XCTAssertFalse(Registry.outputs(input).contains("svg")) }
    }
    func testMixedSelectionUsesCommonOutputs() {
        let s = FileSelection(urls:[URL(fileURLWithPath:"/tmp/photo.jpg"),URL(fileURLWithPath:"/tmp/song.mp3")])
        XCTAssertTrue(Registry.operations(.convert,s).isEmpty); XCTAssertEqual(Registry.operations(.actions,s).count,6)
        let same = FileSelection(urls:[URL(fileURLWithPath:"/tmp/a.jpg"),URL(fileURLWithPath:"/tmp/b.png")])
        XCTAssertFalse(Registry.operations(.convert,same).contains { ["convert:jpg","convert:png"].contains($0.id) })
    }
    func testWheelGeometryAndPagination() async {
        await MainActor.run {
            let application = NSApplication.shared;application.setActivationPolicy(.prohibited)
            let app = AppController.shared;let wheel = WheelController(app:app)
            wheel.selection = FileSelection(urls:[URL(fileURLWithPath:"/tmp/sample.mp4")]);wheel.mode = .tools;wheel.options = Registry.operations(.tools,wheel.selection)
            XCTAssertGreaterThan(wheel.options.count,8)
            XCTAssertNil(wheel.view.index(NSPoint(x:205,y:205)))
            XCTAssertNil(wheel.view.index(NSPoint(x:10,y:10)))
            for index in 0..<wheel.displayed.count {
                let angle = Double(index)*2 * Double.pi/Double(wheel.displayed.count)
                XCTAssertEqual(wheel.view.index(NSPoint(x:205+110*sin(angle),y:205+110*cos(angle))),index)
            }
            let first = wheel.displayed;wheel.changePage(1);XCTAssertNotEqual(first,wheel.displayed);wheel.changePage(-1);XCTAssertEqual(first,wheel.displayed)
        }
    }
    func testWheelClosingDoesNotDismissReopenedPresentation() async throws {
        let wheel = await MainActor.run { () -> WheelController in
            NSApplication.shared.setActivationPolicy(.prohibited)
            let wheel = WheelController(app:AppController.shared,reduceMotion:{ false })
            wheel.options = Registry.actions
            wheel.panel.setFrameOrigin(NSPoint(x:-10000,y:-10000))
            wheel.present()
            let oldID = wheel.presentationID
            wheel.hide()
            XCTAssertFalse(wheel.visible)
            XCTAssertTrue(wheel.panel.ignoresMouseEvents)
            wheel.present()
            wheel.hide(expectedPresentation:oldID)
            XCTAssertTrue(wheel.visible)
            return wheel
        }
        try await Task.sleep(nanoseconds:240_000_000)
        await MainActor.run {
            XCTAssertTrue(wheel.visible)
            XCTAssertTrue(wheel.panel.isVisible)
            XCTAssertFalse(wheel.panel.ignoresMouseEvents)
            wheel.hide()
        }
        try await Task.sleep(nanoseconds:220_000_000)
        await MainActor.run {
            XCTAssertFalse(wheel.panel.isVisible)
            XCTAssertFalse(wheel.visible)
        }
    }
    func testWheelReduceMotionClosesImmediately() async {
        await MainActor.run {
            NSApplication.shared.setActivationPolicy(.prohibited)
            let wheel = WheelController(app:AppController.shared,reduceMotion:{ true })
            wheel.options = Registry.actions
            wheel.panel.setFrameOrigin(NSPoint(x:-10000,y:-10000))
            wheel.present()
            XCTAssertTrue(wheel.visible)
            XCTAssertEqual(wheel.view.animationHost.layer?.opacity,1)
            wheel.hide()
            XCTAssertFalse(wheel.panel.isVisible)
        }
    }
    func testWheelGlassGapsRejectDrops() async {
        await MainActor.run {
            let wheel = WheelController(app:AppController.shared)
            wheel.options = Registry.operations(.convert,FileSelection(urls:[URL(fileURLWithPath:"/tmp/a.jpg")]))
            let angle = Double.pi/2-Double.pi/Double(wheel.displayed.count)
            XCTAssertNil(wheel.view.index(NSPoint(x:205+112*cos(angle),y:205+112*sin(angle))))
            XCTAssertNil(wheel.view.index(NSPoint(x:205,y:205+168)))
        }
    }
    func testPageRanges() throws {
        XCTAssertEqual(try engine.pageIndices("3-1, 4, 2",count:4),[2,1,0,3,1])
        XCTAssertThrowsError(try engine.pageIndices("0",count:4)); XCTAssertThrowsError(try engine.pageIndices("1-8",count:4))
        XCTAssertThrowsError(try engine.pageIndices("x",count:4))
    }
    func testTimelineValidation() throws {
        XCTAssertEqual(try engine.parseTimes("4, 1.5",duration:10),[1.5,4]); XCTAssertThrowsError(try engine.parseTimes("4,4.01",duration:10))
        XCTAssertThrowsError(try engine.parseTimes("nan",duration:10)); XCTAssertThrowsError(try engine.parseRanges("4-1",duration:10))
        XCTAssertThrowsError(try engine.parseRanges("0-99",duration:10)); XCTAssertEqual(try engine.parseRanges("1-3, 5-8",duration:10).count,2)
    }
    func testUniquePublishingAndOriginalPreservation() throws {
        let input = try fixtureImage(); let before = try Data(contentsOf:input)
        let pdf1 = try run("tool:createPDF",[input])[0]; let pdf2 = try run("tool:createPDF",[input])[0]
        XCTAssertNotEqual(pdf1,pdf2); XCTAssertEqual(try Data(contentsOf:input),before)
        XCTAssertEqual(PDFDocument(url:pdf1)?.pageCount,1)
    }
    func testPDFMergeSplitReorderAndRaster() throws {
        let pdf = try fixturePDF()
        let merged = try run("tool:mergePDF",[pdf,pdf])[0]; XCTAssertEqual(PDFDocument(url:merged)?.pageCount,4)
        let split = try run("tool:splitPDF",[pdf]); XCTAssertEqual(split.count,2)
        var options = OperationOptions(); options.pageOrder = "2,1,2"; options.rotation = 90; options.pageRotations = [0:90]
        let ordered = try run("tool:organizePDF",[pdf],options:options)[0]
        XCTAssertEqual(PDFDocument(url:ordered)?.pageCount,3); XCTAssertEqual(PDFDocument(url:ordered)?.page(at:0)?.rotation,90); XCTAssertEqual(PDFDocument(url:ordered)?.page(at:1)?.rotation,180)
        let folder = try run("convert:png",[pdf])[0]; let pages = try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)
        XCTAssertEqual(pages.count,2); XCTAssertNotNil(NSImage(contentsOf:pages[0]))
    }
    func testRedactionFlattensAndConcealsPixels() throws {
        let input = try fixtureImage(); var o = OperationOptions(); o.rectangles = [CGRect(x:0,y:0,width:0.5,height:0.5)]
        let out = try run("tool:redactImage",[input],options:o)[0]
        let bitmap = NSBitmapImageRep(data:try Data(contentsOf:out))!
        let black = bitmap.colorAt(x:10,y:10)!.usingColorSpace(.deviceRGB)!
        let untouched = bitmap.colorAt(x:140,y:100)!.usingColorSpace(.deviceRGB)!
        XCTAssertLessThan(black.redComponent,0.01); XCTAssertGreaterThan(untouched.redComponent,0.9)
    }
    func testCancelledJobPublishesNothing() throws {
        let input = try fixtureImage(); let token = CancellationToken(); token.cancel()
        XCTAssertThrowsError(try Engine(token:token).execute(.init(urls:[input],operation:"tool:createPDF",options:.init())) { _,_ in })
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at:output,includingPropertiesForKeys:nil).isEmpty)
    }
    func testArchiveRoundTripAndTraversalRejection() throws {
        let input = inputs.appendingPathComponent("hello.txt"); try "Hello".write(to:input,atomically:true,encoding:.utf8)
        let zip = inputs.appendingPathComponent("test.zip"); try engine.run("/usr/bin/ditto",["-c","-k",input.path,zip.path])
        let folder = try run("tool:extractArchive",[zip])[0]; XCTAssertEqual(try String(contentsOf:folder.appendingPathComponent("hello.txt")),"Hello")
        let malicious = inputs.appendingPathComponent("unsafe.tar")
        try engine.run("/usr/bin/python3",["-c","import tarfile,io,sys; t=tarfile.open(sys.argv[1],'w'); i=tarfile.TarInfo('../escape.txt'); i.size=1; t.addfile(i,io.BytesIO(b'x')); t.close()",malicious.path])
        XCTAssertThrowsError(try run("tool:extractArchive",[malicious]))
        let links = inputs.appendingPathComponent("links.tar")
        try engine.run("/usr/bin/python3",["-c","import tarfile,sys; t=tarfile.open(sys.argv[1],'w'); i=tarfile.TarInfo('link'); i.type=tarfile.SYMTYPE; i.linkname='/tmp'; t.addfile(i); t.close()",links.path])
        XCTAssertThrowsError(try run("tool:extractArchive",[links]))
    }
    func testImageFormatsAndTools() throws {
        try requireTools(); let input = try fixtureImage()
        for ext in Registry.outputs("png") {
            let result = try run("convert:"+ext,[input]); XCTAssertFalse(result.isEmpty)
            if ext != "pdf" { XCTAssertGreaterThan(engine.fileSize(result[0]),20) }
        }
        for tool in ["compress","metadata","editImage","annotateImage","frameImage","cropImage","createCollage"] {
            var o = OperationOptions(); o.width = 80; o.height = 60; o.annotation = "Test"; o.rectangles = [CGRect(x:0.1,y:0.1,width:0.5,height:0.5)]
            let result = try run("tool:"+tool,[input],options:o); XCTAssertGreaterThan(engine.fileSize(result[0]),20)
        }
    }
    func fixtureVideo() throws -> URL {
        let video = inputs.appendingPathComponent("video.mp4")
        try engine.ff(["-f","lavfi","-i","testsrc=size=160x120:rate=15","-f","lavfi","-i","sine=frequency=440:sample_rate=48000","-t","1.5","-c:v","libx264","-pix_fmt","yuv420p","-c:a","aac",video.path]); return video
    }
    func testMediaFormatsAndTools() throws {
        try requireTools(); let video = try fixtureVideo()
        for ext in Registry.outputs("mp4") { let urls = try run("convert:"+ext,[video]); XCTAssertGreaterThan(engine.fileSize(urls[0]),20) }
        let audio = try run("convert:mp3",[video])[0]
        for ext in Registry.outputs("mp3") { let urls = try run("convert:"+ext,[audio]); XCTAssertGreaterThan(engine.fileSize(urls[0]),20) }
        for tool in ["compress","muteVideo","trimVideo","cropVideo","changeVideoSpeed","splitVideo","videoSnapshots","redactVideo","joinVideos"] {
            var o = OperationOptions(); o.start = 0.1; o.end = 1.1; o.width = 80; o.height = 60; o.speed = 1.5; o.splitTimes = "0.5"; o.rectangles = [CGRect(x:0.1,y:0.1,width:0.5,height:0.5)]
            let urls = try run("tool:"+tool,[video],options:o); XCTAssertFalse(urls.isEmpty)
        }
        for tool in ["normalizeAudio","audioChannels","trimAudio","redactAudio","audioToVideo"] {
            var o = OperationOptions(); o.start = 0.1; o.end = 1.1; o.redactRanges = "0.2-0.5"
            let urls = try run("tool:"+tool,[audio],options:o); XCTAssertGreaterThan(engine.fileSize(urls[0]),20)
        }
    }
    func testAudioRedactionPreservesUnselectedSamples() throws {
        try requireTools()
        let input = inputs.appendingPathComponent("tone.wav")
        try engine.ff(["-f","lavfi","-i","sine=frequency=440:sample_rate=48000","-t","2","-c:a","pcm_s16le",input.path])
        var o = OperationOptions();o.redactRanges = "0.5-1.2"
        let redacted = try run("tool:redactAudio",[input],options:o)[0]
        func samples(_ url:URL,start:String) throws -> [Float] {
            let file = root.appendingPathComponent(UUID().uuidString + ".raw")
            try engine.ff(["-ss",start,"-i",url.path,"-t","0.15","-f","f32le",file.path])
            return try Data(contentsOf:file).withUnsafeBytes { Array($0.bindMemory(to:Float.self)) }
        }
        let original = try samples(input,start:"0.1"),clean = try samples(redacted,start:"0.1")
        XCTAssertEqual(original.count,clean.count)
        XCTAssertLessThan(zip(original,clean).map { abs($0-$1) }.max() ?? 1,0.0001)
        let changed = try samples(redacted,start:"0.7"),source = try samples(input,start:"0.7")
        XCTAssertGreaterThan(zip(changed,source).map { abs($0-$1) }.max() ?? 0,0.01)
    }
    func testSpeedRespectsInputRange() throws {
        try requireTools();let video = try fixtureVideo();var o = OperationOptions();o.start = 0.2;o.end = 1.2;o.speed = 2
        let output = try run("tool:changeVideoSpeed",[video],options:o)[0]
        XCTAssertEqual(engine.duration(output),0.5,accuracy:0.18)
    }
    func testPDFMetadataRewritePreservesText() throws {
        let pdf = try fixturePDF();let original = PDFDocument(url:pdf)!
        original.documentAttributes = [PDFDocumentAttribute.authorAttribute:"Private Author"]
        XCTAssertTrue(original.write(to:pdf))
        let cleaned = try run("tool:metadata",[pdf])[0]
        XCTAssertEqual(PDFDocument(url:cleaned)?.pageCount,2)
        XCTAssertNil(PDFDocument(url:cleaned)?.documentAttributes?[PDFDocumentAttribute.authorAttribute])
    }
    func testScannedPDFUsesLocalOCR() throws {
        let image = inputs.appendingPathComponent("scan.png")
        let ctx = CGContext(data:nil,width:600,height:200,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray:1,alpha:1));ctx.fill(CGRect(x:0,y:0,width:600,height:200))
        let attr = NSAttributedString(string:"Clementine OCR",attributes:[.font:CTFontCreateWithName("Helvetica" as CFString,36,nil),.foregroundColor:CGColor(gray:0,alpha:1)])
        ctx.textPosition = CGPoint(x:20,y:100);CTLineDraw(CTLineCreateWithAttributedString(attr),ctx)
        try engine.writeCGImage(ctx.makeImage()!,to:image)
        let pdf = inputs.appendingPathComponent("scan.pdf");try engine.imagesPDF([image],to:pdf)
        XCTAssertTrue(try engine.pdfTexts(pdf).joined().contains("Clementine"))
    }
    func testDocumentConversions() throws {
        try requireTools()
        let txt = inputs.appendingPathComponent("story.txt"); try "Clementine\n\nA short document with editable text.\n\nName  Value\nApples  12".write(to:txt,atomically:true,encoding:.utf8)
        for ext in ["docx","md","html","epub","pdf","jpg","png"] {
            let urls = try run("convert:"+ext,[txt]); XCTAssertFalse(urls.isEmpty)
            if ext == "pdf" { XCTAssertGreaterThan(PDFDocument(url:urls[0])?.pageCount ?? 0,0) }
        }
        let pdf = try run("convert:pdf",[txt])[0]
        for ext in ["txt","md","docx","pptx","xlsx","epub"] {
            let urls = try run("convert:"+ext,[pdf]); XCTAssertGreaterThan(engine.fileSize(urls[0]),20)
            if ["txt","md"].contains(ext) { XCTAssertTrue(try String(contentsOf:urls[0]).contains("editable text")) }
        }
    }
}
