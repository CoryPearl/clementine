import Foundation
import AppKit
import PDFKit
import Vision
import ImageIO
import CoreImage
import CoreGraphics

extension Engine {
    func cleanPDFMetadata(_ input:URL,to output:URL) throws {
        guard let source = CGPDFDocument(input as CFURL),!source.isEncrypted,let context = CGContext(output as CFURL,mediaBox:nil,nil) else { throw ClementineError.message("Cannot rewrite PDF metadata.") }
        let visibleDocument = PDFDocument(url:input)
        for i in 1...max(1,source.numberOfPages) {
            try token.check();guard let page = source.page(at:i) else { continue }
            let bounds = page.getBoxRect(.mediaBox)
            var box = bounds
            let boxData = Data(bytes:&box,count:MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox as String:boxData] as CFDictionary)
            if let visiblePage = visibleDocument?.page(at:i-1) { visiblePage.draw(with:.mediaBox,to:context) }
            else { context.drawPDFPage(page) }
            context.endPDFPage()
        };context.closePDF()
    }
    func imagesPDF(_ inputs:[URL],to output:URL) throws {
        let pdf = PDFDocument()
        for input in inputs {
            try token.check()
            var image = NSImage(contentsOf:input)
            if image == nil {
                let temp = output.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".png")
                try self.image(input,to:temp,options:OperationOptions()); image = NSImage(contentsOf:temp); try? FileManager.default.removeItem(at:temp)
            }
            guard let image, let page = PDFPage(image:image) else { throw ClementineError.message("Cannot load \(input.lastPathComponent) as an image.") }
            pdf.insert(page,at:pdf.pageCount)
        }
        guard pdf.write(to:output) else { throw ClementineError.message("Could not write the PDF.") }
    }
    func mergePDF(_ inputs:[URL],to output:URL) throws {
        let result = PDFDocument()
        for input in inputs {
            guard let pdf = PDFDocument(url:input), !pdf.isLocked else { throw ClementineError.message("A PDF is unreadable or password protected.") }
            for i in 0..<pdf.pageCount { try token.check(); if let page = pdf.page(at:i)?.copy() as? PDFPage { result.insert(page,at:result.pageCount) } }
        }
        guard result.write(to:output) else { throw ClementineError.message("Could not write the combined PDF.") }
    }
    func pageIndices(_ text:String,count:Int) throws -> [Int] {
        if text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { return Array(0..<count) }
        var indices:[Int] = []
        for part in text.split(separator:",") {
            let range = part.trimmingCharacters(in:.whitespaces).split(separator:"-")
            guard (1...2).contains(range.count), let a = Int(range[0]), a >= 1, a <= count else { throw ClementineError.message("Enter page numbers or ranges, such as 1, 3-5, 2.") }
            if range.count == 2 {
                guard let b = Int(range[1]), b >= 1, b <= count else { throw ClementineError.message("A page range is outside the document.") }
                indices += stride(from:a-1,through:b-1,by:b >= a ? 1 : -1)
            } else { indices.append(a-1) }
        }
        guard !indices.isEmpty else { throw ClementineError.message("Choose at least one page.") }; return indices
    }
    func organizePDF(_ input:URL,to output:URL,order:String,rotation:Double,rotations:[Int:Int] = [:]) throws {
        guard let pdf = PDFDocument(url:input), !pdf.isLocked else { throw ClementineError.message("Cannot open the PDF. Unlock password-protected files first.") }
        let result = PDFDocument()
        for i in try pageIndices(order,count:pdf.pageCount) { try token.check(); if let page = pdf.page(at:i)?.copy() as? PDFPage { page.rotation = (page.rotation + Int(rotation) + (rotations[i] ?? 0)) % 360; result.insert(page,at:result.pageCount) } }
        guard result.write(to:output) else { throw ClementineError.message("Could not write the organized PDF.") }
    }
    func splitPDF(_ input:URL,order:String,groups:Bool,work:URL) throws -> [URL] {
        guard let pdf = PDFDocument(url:input), !pdf.isLocked else { throw ClementineError.message("Cannot open the PDF.") }
        let chunks: [[Int]]
        if groups && !order.isEmpty { chunks = try order.split(separator:",").map { try pageIndices(String($0),count:pdf.pageCount) } }
        else { chunks = try pageIndices(order,count:pdf.pageCount).map { [$0] } }
        var result:[URL] = []
        for (n,indices) in chunks.enumerated() {
            try token.check(); let part = PDFDocument()
            for i in indices { if let page = pdf.page(at:i)?.copy() as? PDFPage { part.insert(page,at:part.pageCount) } }
            let out = named(input,"pdf",work,suffix:String(format:" - Part %03d",n+1))
            guard part.write(to:out) else { throw ClementineError.message("Could not split the PDF.") }; result.append(out)
        }; return result
    }
    func rasterizePDF(_ input:URL,to ext:String,work:URL,dpi:Double = 300) throws -> [URL] {
        guard let pdf = PDFDocument(url:input), !pdf.isLocked else { throw ClementineError.message("Cannot read the PDF.") }
        let folder = work.appendingPathComponent(input.deletingPathExtension().lastPathComponent + " - Pages")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        for i in 0..<pdf.pageCount {
            try token.check(); guard let page = pdf.page(at:i) else { continue }
            let bounds = page.bounds(for:.mediaBox); let scale = dpi/72
            let w = Int(bounds.width*scale), h = Int(bounds.height*scale)
            guard w > 0,h > 0,w <= 30000,h <= 30000,Int64(w)*Int64(h) <= 150_000_000,
                  let ctx = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ClementineError.message("A PDF page is too large to render safely.") }
            ctx.setFillColor(CGColor(gray:1,alpha:1)); ctx.fill(CGRect(x:0,y:0,width:w,height:h)); ctx.scaleBy(x:scale,y:scale)
            ctx.translateBy(x:-bounds.minX,y:-bounds.minY); page.draw(with:.mediaBox,to:ctx)
            guard let image = ctx.makeImage() else { continue }
            let output = folder.appendingPathComponent(String(format:"Page %03d.%@",i+1,ext))
            try writeCGImage(image,to:output)
        }
        return [folder]
    }
    func writeCGImage(_ image:CGImage,to output:URL) throws {
        let type = output.pathExtension == "jpg" ? "public.jpeg" : "public.png"
        guard let dest = CGImageDestinationCreateWithURL(output as CFURL,type as CFString,1,nil) else { throw ClementineError.message("Could not create the image output.") }
        CGImageDestinationAddImage(dest,image,[kCGImageDestinationLossyCompressionQuality:0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ClementineError.message("Could not write the image.") }
    }
    func compressPDF(_ input:URL,to output:URL,quality:Double) throws {
        // Raster compression removes hidden original streams and gives predictable portable output.
        let folder = output.deletingLastPathComponent().appendingPathComponent("raster")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let pages = try rasterizePDF(input,to:"jpg",work:folder,dpi:quality < 50 ? 100 : 150)[0]
        let images = try FileManager.default.contentsOfDirectory(at:pages,includingPropertiesForKeys:nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
        try imagesPDF(images,to:output)
    }
    func pdfTexts(_ input:URL) throws -> [String] {
        guard let pdf = PDFDocument(url:input),!pdf.isLocked else { throw ClementineError.message("Cannot read this PDF.") }
        var pages:[String] = []
        for i in 0..<pdf.pageCount {
            try token.check(); guard let page = pdf.page(at:i) else { continue }
            var text = page.string ?? ""
            if text.trimmingCharacters(in:.whitespacesAndNewlines).count < 5 {
                let size = page.bounds(for:.mediaBox).size
                let thumb = page.thumbnail(of:NSSize(width:min(2400,size.width*3),height:min(3200,size.height*3)),for:.mediaBox)
                if let cg = thumb.cgImage(forProposedRect:nil,context:nil,hints:nil) {
                    let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
                    try VNImageRequestHandler(cgImage:cg).perform([request])
                    text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator:"\n") ?? ""
                }
            }
            pages.append(text)
        }; return pages
    }
    func pdfConvert(_ input:URL,to ext:String,options o:OperationOptions,work:URL) throws -> [URL] {
        if ["png","jpg"].contains(ext) { return try rasterizePDF(input,to:ext,work:work) }
        let texts = try pdfTexts(input); let output = named(input,ext,work)
        let artwork = ["docx","pages","epub","pptx"].contains(ext) ? try pdfArtwork(input,work:work) : []
        if ["txt","md"].contains(ext) { try texts.joined(separator:"\n\n\u{000C}\n\n").write(to:output,atomically:true,encoding:.utf8); return [output] }
        if ext == "pptx" { try writeSlides(texts,to:output,artwork:artwork); return [output] }
        if ext == "xlsx" { try writeWorkbook(texts,to:output); return [output] }
        let html = work.appendingPathComponent("reconstructed.html")
        let body = texts.enumerated().map { i,text in
            let paragraphs = text.components(separatedBy:"\n").map { line in
                if line.contains("\t") { return "<table><tr>" + line.components(separatedBy:"\t").map { "<td>\(xml($0))</td>" }.joined() + "</tr></table>" }
                return "<p>\(xml(line))</p>"
            }.joined()
            let images = (artwork.indices.contains(i) ? artwork[i] : []).compactMap { url -> String? in
                guard let data = try? Data(contentsOf:url) else { return nil }
                return "<p><img src=\"data:image/png;base64,\(data.base64EncodedString())\" style=\"max-width:600px\" /></p>"
            }.joined()
            return "<section><h2>Page \(i+1)</h2>" + paragraphs + images + "</section>"
        }.joined()
        try ("<!doctype html><html><head><meta charset='utf-8'><title>\(xml(input.deletingPathExtension().lastPathComponent))</title></head><body>" + body + "</body></html>").write(to:html,atomically:true,encoding:.utf8)
        if ext == "pages" {
            let docx = work.appendingPathComponent("reconstructed.docx"); try pandoc(html,to:docx)
            try appleConvert(docx,to:output,app:"Pages",format:"pages")
        } else { try pandoc(html,to:output) }
        return [output]
    }
    func xml(_ text:String) -> String { text.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;") }
    func writeXML(_ text:String,_ path:String,_ root:URL) throws { let u = root.appendingPathComponent(path); try FileManager.default.createDirectory(at:u.deletingLastPathComponent(),withIntermediateDirectories:true); try text.write(to:u,atomically:true,encoding:.utf8) }
    func zipPackage(_ root:URL,to output:URL) throws { try run("/usr/bin/ditto",["-c","-k","--norsrc",root.path,output.path]) }
    func writeWorkbook(_ texts:[String],to output:URL) throws {
        let root = output.deletingLastPathComponent().appendingPathComponent("xlsx-\(UUID().uuidString)")
        var types = "", sheets = "", rels = ""
        for (i,text) in texts.enumerated() {
            let n = i+1; types += "<Override PartName=\"/xl/worksheets/sheet\(n).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
            sheets += "<sheet name=\"Page \(n)\" sheetId=\"\(n)\" r:id=\"rId\(n)\"/>"
            rels += "<Relationship Id=\"rId\(n)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(n).xml\"/>"
            var rows = ""
            for (r,line) in text.components(separatedBy:"\n").enumerated() {
                let cells = line.components(separatedBy:try NSRegularExpression(pattern:"\\t| {2,}"))
                rows += "<row r=\"\(r+1)\">" + cells.enumerated().map { c,value in
                    var col = ""; var v = c+1; while v > 0 { v -= 1; col = String(UnicodeScalar(65+v%26)!) + col; v /= 26 }
                    return "<c r=\"\(col)\(r+1)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xml(value))</t></is></c>"
                }.joined() + "</row>"
            }
            try writeXML("<?xml version=\"1.0\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>\(rows)</sheetData></worksheet>","xl/worksheets/sheet\(n).xml",root)
        }
        try writeXML("<?xml version=\"1.0\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>\(types)</Types>","[Content_Types].xml",root)
        try writeXML("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>","_rels/.rels",root)
        try writeXML("<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>\(sheets)</sheets></workbook>","xl/workbook.xml",root)
        try writeXML("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(rels)</Relationships>","xl/_rels/workbook.xml.rels",root)
        try zipPackage(root,to:output)
    }
    func writeSlides(_ texts:[String],to output:URL,artwork:[[URL]] = []) throws {
        // Use LibreOffice's Flat ODF importer to produce a fully editable presentation.
        let fodp = output.deletingLastPathComponent().appendingPathComponent("reconstructed.fodp")
        let slides = texts.enumerated().map { i,text in
            let paragraphs = text.components(separatedBy:"\n").map { "<text:p>\(xml($0))</text:p>" }.joined()
            let images = (artwork.indices.contains(i) ? artwork[i] : []).prefix(3).enumerated().compactMap { n,url -> String? in
                guard let data = try? Data(contentsOf:url) else { return nil }
                return "<draw:frame svg:x=\"\(1+n*8)cm\" svg:y=\"13cm\" svg:width=\"7cm\" svg:height=\"5cm\"><draw:image><office:binary-data>\(data.base64EncodedString())</office:binary-data></draw:image></draw:frame>"
            }.joined()
            return "<draw:page draw:name=\"Page \(i+1)\" draw:master-page-name=\"Default\"><draw:frame svg:x=\"1cm\" svg:y=\"1cm\" svg:width=\"24cm\" svg:height=\"12cm\"><draw:text-box>\(paragraphs)</draw:text-box></draw:frame>\(images)</draw:page>"
        }.joined()
        try ("<?xml version=\"1.0\"?><office:document xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:draw=\"urn:oasis:names:tc:opendocument:xmlns:drawing:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" xmlns:svg=\"urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0\" xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\" office:mimetype=\"application/vnd.oasis.opendocument.presentation\" office:version=\"1.3\"><office:styles/><office:automatic-styles/><office:master-styles><style:master-page style:name=\"Default\"/></office:master-styles><office:body><office:presentation>\(slides)</office:presentation></office:body></office:document>").write(to:fodp,atomically:true,encoding:.utf8)
        try libreoffice(fodp,to:output)
    }
    func pandoc(_ input:URL,to output:URL) throws {
        let map = ["md":"markdown","txt":"plain","html":"html","epub":"epub3","docx":"docx"]
        let from = ["md":"markdown","txt":"markdown","html":"html","epub":"epub","docx":"docx","rtf":"rtf"][Registry.ext(input)] ?? "html"
        try run(try tool("pandoc"),["--sandbox","--from",from,"--to",map[output.pathExtension] ?? output.pathExtension,"--standalone","--metadata","title=\(input.deletingPathExtension().lastPathComponent)","--output",output.path,input.path])
    }
    func libreoffice(_ input:URL,to output:URL) throws {
        let office = Self.toolsRoot.appendingPathComponent("LibreOffice.app/Contents/MacOS/soffice").path
        guard FileManager.default.isExecutableFile(atPath:office) else { throw ClementineError.message("The bundled LibreOffice engine is missing.") }
        let folder = output.deletingLastPathComponent().appendingPathComponent("lo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let profile = folder.appendingPathComponent("profile")
        let userProfile = profile.appendingPathComponent("user")
        try FileManager.default.createDirectory(at:userProfile,withIntermediateDirectories:true)
        let registry = """
        <?xml version="1.0"?><oor:items xmlns:oor="http://openoffice.org/2001/registry"><item oor:path="/org.openoffice.Office.Common/Security/Scripting"><prop oor:name="MacroSecurityLevel" oor:op="fuse"><value>3</value></prop></item><item oor:path="/org.openoffice.Office.Common/Load"><prop oor:name="UpdateLinks" oor:op="fuse"><value>0</value></prop></item></oor:items>
        """
        try registry.write(to:userProfile.appendingPathComponent("registrymodifications.xcu"),atomically:true,encoding:.utf8)
        let formats = ["docx":"docx:Office Open XML Text","pptx":"pptx:Impress MS PowerPoint 2007 XML","xlsx":"xlsx:Calc MS Excel 2007 XML","tsv":"csv:Text - txt - csv (StarCalc):9,34,76,1","csv":"csv:Text - txt - csv (StarCalc):44,34,76,1"]
        _ = try run(office,["-env:UserInstallation=\(profile.absoluteString)","--headless","--nologo","--nodefault","--norestore","--convert-to",formats[output.pathExtension] ?? output.pathExtension,"--outdir",folder.path,input.path],timeout:300)
        let resultExt = output.pathExtension == "tsv" ? "csv" : output.pathExtension
        let result = folder.appendingPathComponent(input.deletingPathExtension().lastPathComponent).appendingPathExtension(resultExt)
        guard FileManager.default.fileExists(atPath:result.path) else { throw ClementineError.message("LibreOffice could not convert this document. It may be encrypted or unsupported.") }
        try FileManager.default.moveItem(at:result,to:output)
    }
    func appleConvert(_ input:URL,to output:URL,app:String,format:String) throws {
        if ProcessInfo.processInfo.environment["CLEMENTINE_DISABLE_APPLE_AUTOMATION"] == "1" { throw ClementineError.message("Apple application automation is disabled for this verification run.") }
        let formats = ["Pages":["docx":"Microsoft Word","pdf":"PDF","txt":"unformatted text","epub":"EPUB"],"Numbers":["xlsx":"Microsoft Excel","pdf":"PDF","csv":"CSV"],"Keynote":["pptx":"Microsoft PowerPoint","pdf":"PDF"]]
        let body: String
        if ["pages","numbers","key"].contains(format) { body = "save d in (POSIX file (item 2 of argv))" }
        else if let value = formats[app]?[format] { body = "export d to (POSIX file (item 2 of argv)) as \(value)" }
        else { throw ClementineError.message("Unsupported Apple application export.") }
        let script = """
        on run argv
            tell application "\(app)"
                set d to open (POSIX file (item 1 of argv))
                try
                    \(body)
                on error errorText number errorNumber
                    close d saving no
                    error errorText number errorNumber
                end try
                close d saving no
            end tell
        end run
        """
        try run("/usr/bin/osascript",["-e",script,input.path,output.path],timeout:300)
    }
    func office(_ input:URL,to ext:String,options o:OperationOptions,work:URL) throws -> [URL] {
        var source = input; let inputExt = Registry.ext(input)
        let output = named(input,ext,work)
        let nativeApp = ["pages":"Pages","numbers":"Numbers","key":"Keynote"][inputExt]
        if let app = nativeApp {
            let bridgeExt = app == "Pages" ? "docx" : app == "Numbers" ? "xlsx" : "pptx"
            let bridge = work.appendingPathComponent("apple-input.\(bridgeExt)")
            try appleConvert(input,to:bridge,app:app,format:bridgeExt); source = bridge
        }
        if inputExt == "textclipping" {
            let data = try Data(contentsOf:input)
            if let plist = try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any],let values = plist["UTI-Data"] as? [String:Any] {
                if let rtf = values["public.rtf"] as? Data {
                    let attr = try NSAttributedString(data:rtf,options:[.documentType:NSAttributedString.DocumentType.rtf],documentAttributes:nil)
                    source = work.appendingPathComponent("clipping.html")
                    try attr.data(from:NSRange(location:0,length:attr.length),documentAttributes:[.documentType:NSAttributedString.DocumentType.html]).write(to:source)
                } else if let utf8 = values["public.utf8-plain-text"] as? Data {
                    source = work.appendingPathComponent("clipping.txt"); try utf8.write(to:source)
                } else { throw ClementineError.message("This text clipping has no supported text representation.") }
            } else { throw ClementineError.message("This legacy text clipping could not be read. Open it in Finder and save its text first.") }
        }
        if inputExt == "rtfd" || inputExt == "rtf" {
            let options:[NSAttributedString.DocumentReadingOptionKey:Any] = [:]
            let attributed = try NSAttributedString(url:input,options:options,documentAttributes:nil)
            let html = try attributed.data(from:NSRange(location:0,length:attributed.length),documentAttributes:[.documentType:NSAttributedString.DocumentType.html])
            source = work.appendingPathComponent("rich-text.html"); try html.write(to:source)
        }
        if ["png","jpg"].contains(ext) {
            let pdf = work.appendingPathComponent("rendered.pdf")
            _ = try office(source,to:"pdf",options:o,work:work.appendingPathComponent("intermediate",isDirectory:true).creatingDirectory())
            let intermediate = work.appendingPathComponent("intermediate").appendingPathComponent(source.deletingPathExtension().lastPathComponent + ".pdf")
            try FileManager.default.copyItem(at:intermediate,to:pdf)
            return try rasterizePDF(pdf,to:ext,work:work)
        }
        if ext == "pages" {
            let docx = work.appendingPathComponent("pages-input.docx")
            if Registry.ext(source) == "docx" { try FileManager.default.copyItem(at:source,to:docx) }
            else { try pandoc(source,to:docx) }
            try appleConvert(docx,to:output,app:"Pages",format:"pages"); return [output]
        }
        let textFormats = ["docx","md","txt","html","epub"]
        if textFormats.contains(Registry.ext(source)) && textFormats.contains(ext) { try pandoc(source,to:output) }
        else if ext == "pdf" && ["epub","md","txt"].contains(Registry.ext(source)) {
            let html = work.appendingPathComponent("print.html"); try pandoc(source,to:html); try libreoffice(html,to:output)
        } else { try libreoffice(source,to:output) }
        return [output]
    }
    func subtitle(_ input:URL,to output:URL) throws {
        let text = try String(contentsOf:input,encoding:.utf8).replacingOccurrences(of:"\r\n",with:"\n")
        if output.pathExtension == "txt" {
            let lines = text.components(separatedBy:"\n").filter { line in
                !line.contains("-->") && !line.trimmingCharacters(in:.whitespaces).isEmpty && Int(line.trimmingCharacters(in:.whitespaces)) == nil && !line.hasPrefix("WEBVTT")
            }
            try lines.joined(separator:"\n").replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression).write(to:output,atomically:true,encoding:.utf8)
        } else { try ff(["-i",input.path,output.path]) }
    }
    func extractArchive(_ input:URL,to output:URL) throws {
        let names = try run("/usr/bin/tar",["-tf",input.path])
        for name in names.components(separatedBy:"\n") where !name.isEmpty {
            let parts = name.replacingOccurrences(of:"\\",with:"/").components(separatedBy:"/")
            guard !name.hasPrefix("/"), !parts.contains(".."), !name.contains("\u{0000}") else { throw ClementineError.message("Archive contains an unsafe path.") }
        }
        let detail = try run("/usr/bin/tar",["-tvf",input.path])
        for line in detail.components(separatedBy:"\n") where !line.isEmpty {
            guard let first = line.first, ["-","d"].contains(first) else { throw ClementineError.message("Archives containing links or special files are not extracted.") }
        }
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        try run("/usr/bin/tar",["-xf",input.path,"-C",output.path,"--no-same-owner","--no-same-permissions"],timeout:900)
    }
}
extension URL {
    func creatingDirectory() throws -> URL { try FileManager.default.createDirectory(at:self,withIntermediateDirectories:true); return self }
}
extension String {
    func components(separatedBy regex:NSRegularExpression) -> [String] {
        var result:[String] = []; var last = startIndex
        for match in regex.matches(in:self,range:NSRange(startIndex...,in:self)) {
            if let range = Range(match.range,in:self) { result.append(String(self[last..<range.lowerBound])); last = range.upperBound }
        }; result.append(String(self[last...])); return result
    }
}
