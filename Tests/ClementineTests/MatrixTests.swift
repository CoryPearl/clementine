import XCTest
import AppKit
import PDFKit
@testable import Clementine

final class MatrixTests:XCTestCase {
    func testEveryReferenceConversion() throws {
        guard ProcessInfo.processInfo.environment["CLEMENTINE_FULL_MATRIX"] == "1" else { throw XCTSkip("Set CLEMENTINE_FULL_MATRIX=1 for the complete 275-route integration run.") }
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("Clementine-matrix-\(UUID().uuidString)")
        try manager.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? manager.removeItem(at:root) }
        let engine = Engine(token:CancellationToken());var fixtures:[String:URL] = [:];var fixtureErrors:[String:String] = [:]
        func fixture(_ ext:String,_ block:() throws -> URL) { do { fixtures[ext] = try block() } catch { fixtureErrors[ext] = error.localizedDescription } }
        func convert(_ input:URL,_ ext:String) throws -> URL {
            let folder = root.appendingPathComponent(UUID().uuidString);try manager.createDirectory(at:folder,withIntermediateDirectories:true)
            var options = OperationOptions();options.destination = folder
            return try engine.execute(.init(urls:[input],operation:"convert:"+ext,options:options)) { _,_ in }[0]
        }
        let png = root.appendingPathComponent("sample.png")
        let ctx = CGContext(data:nil,width:96,height:64,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red:1,green:0.5,blue:0.2,alpha:1));ctx.fill(CGRect(x:0,y:0,width:96,height:64));try engine.writeCGImage(ctx.makeImage()!,to:png);fixtures["png"] = png
        for ext in Registry.images where ext != "png" && ext != "svg" { fixture(ext) { try convert(png,ext) } }
        let svg = root.appendingPathComponent("sample.svg");try "<svg xmlns='http://www.w3.org/2000/svg' width='96' height='64'><rect width='96' height='64' fill='#f56d29'/></svg>".write(to:svg,atomically:true,encoding:.utf8);fixtures["svg"] = svg
        let video = root.appendingPathComponent("sample.mp4")
        try engine.ff(["-f","lavfi","-i","testsrc=size=96x64:rate=10","-f","lavfi","-i","sine=frequency=440:sample_rate=48000","-t","0.6","-c:v","libx264","-pix_fmt","yuv420p","-c:a","aac",video.path]);fixtures["mp4"] = video
        for ext in Registry.videos + ["gif"] + Registry.audios where ext != "mp4" { fixture(ext) { try convert(video,ext) } }
        let txt = root.appendingPathComponent("sample.txt");try "Clementine\n\nEditable text, café, and fruit.\nName  Count\nClementine  12".write(to:txt,atomically:true,encoding:.utf8);fixtures["txt"] = txt
        for ext in ["docx","md","epub","pdf"] { fixture(ext) { try convert(txt,ext) } }
        let rich = NSAttributedString(string:"Clementine\nEditable rich text.")
        let rtf = root.appendingPathComponent("sample.rtf");try rich.data(from:NSRange(location:0,length:rich.length),documentAttributes:[.documentType:NSAttributedString.DocumentType.rtf]).write(to:rtf);fixtures["rtf"] = rtf
        let rtfd = root.appendingPathComponent("sample.rtfd");let wrapper = try rich.fileWrapper(from:NSRange(location:0,length:rich.length),documentAttributes:[.documentType:NSAttributedString.DocumentType.rtfd]);try wrapper.write(to:rtfd,options:.atomic,originalContentsURL:nil);fixtures["rtfd"] = rtfd
        let clipping = root.appendingPathComponent("sample.textClipping");try PropertyListSerialization.data(fromPropertyList:["UTI-Data":["public.utf8-plain-text":Data("Clementine clipping".utf8)]],format:.binary,options:0).write(to:clipping);fixtures["textclipping"] = clipping
        let csv = root.appendingPathComponent("sample.csv");try "Name,Count\nClementine,12\nOrange,6\n".write(to:csv,atomically:true,encoding:.utf8);fixtures["csv"] = csv
        for ext in ["xlsx","ods","tsv"] { fixture(ext) { try convert(csv,ext) } }
        fixture("xls") { let out = root.appendingPathComponent("sample.xls");try engine.libreoffice(csv,to:out);return out }
        if let pdf = fixtures["pdf"] {
            fixture("pptx") { try convert(pdf,"pptx") }
            if let pptx = fixtures["pptx"] { fixture("ppt") { let out = root.appendingPathComponent("sample.ppt");try engine.libreoffice(pptx,to:out);return out } }
        }
        fixtureErrors["pages"] = "Apple app automation is excluded from automated testing at the user's request."
        let srt = root.appendingPathComponent("sample.srt");try "1\n00:00:00,000 --> 00:00:00,500\nClementine\n\n".write(to:srt,atomically:true,encoding:.utf8);fixtures["srt"] = srt;fixture("vtt") { try convert(srt,"vtt") }
        let zip = root.appendingPathComponent("sample.zip");try engine.run("/usr/bin/ditto",["-c","-k",txt.path,zip.path]);fixtures["zip"] = zip
        for ext in ["tar","gz"] { fixture(ext) { try convert(zip,ext) } }
        let sourceRoot = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
        fixtures["rar"] = sourceRoot.appendingPathComponent("Fixtures/sample.rar")
        var results:[[String:String]] = []
        let inputs = Registry.images + Registry.audios + Registry.videos + ["gif","pdf","ppt","pptx","docx","pages","md","rtf","rtfd","textclipping","epub","txt"] + Registry.sheets + ["srt","vtt"] + Registry.archives
        for ext in inputs {
            for target in Registry.outputs(ext) {
                var row = ["input":ext,"output":target]
                if ext == "pages" || target == "pages" {
                    row["status"] = "manual-check"
                    row["error"] = "Pages automation is excluded from automated testing at the user's request."
                } else if let input = fixtures[ext] {
                    do {
                        let output = try convert(input,target)
                        var directory:ObjCBool = false
                        XCTAssertTrue(manager.fileExists(atPath:output.path,isDirectory:&directory))
                        if directory.boolValue { XCTAssertFalse(try manager.contentsOfDirectory(atPath:output.path).isEmpty) }
                        else { XCTAssertGreaterThan(engine.fileSize(output),0) }
                        if target == "pdf" { XCTAssertGreaterThan(PDFDocument(url:output)?.pageCount ?? 0,0) }
                        row["status"] = "passed"
                    } catch { row["status"] = "failed";row["error"] = error.localizedDescription }
                } else { row["status"] = "unavailable-input";row["error"] = fixtureErrors[ext] ?? "No fixture" }
                results.append(row)
                print("MATRIX \(ext) → \(target): \(row["status"]!)")
            }
        }
        let report = sourceRoot.deletingLastPathComponent().appendingPathComponent("dist/verification")
        try manager.createDirectory(at:report,withIntermediateDirectories:true)
        try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:report.appendingPathComponent("conversions.json"))
        let failures = results.filter { $0["status"] == "failed" || $0["status"] == "unavailable-input" }
        XCTAssertEqual(results.count,275)
        XCTAssertTrue(failures.isEmpty,"\(failures.count) routes failed. See dist/verification/conversions.json")
    }
}
