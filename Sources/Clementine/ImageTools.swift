import Foundation
import AppKit
import CoreGraphics
import CoreImage
import CoreText
import Vision

extension Engine {
    func loadEditableImage(_ input:URL,maximumDimension:Int = 30000) throws -> CGImage {
        if let image = try? ImageRendering.load(input,maximumDimension:maximumDimension) { return image }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Clementine-image-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let raster = directory.appendingPathComponent("source.png")
        try image(input,to:raster,options:OperationOptions())
        return try ImageRendering.load(raster,maximumDimension:maximumDimension)
    }
    func renderImage(_ input:URL,to output:URL,tool t:Tool,options o:OperationOptions) throws {
        var source = try loadEditableImage(input)
        if t == .removeBackground || o.removeBackground { source = try ImageRendering.removeBackground(source) }
        if t == .redactImage && o.rectangles.isEmpty { throw ClementineError.message("Draw an area to redact, or detect faces or text first.") }
        let result = try ImageRendering.render(source,tool:t,options:o)
        try token.check()
        if ["png","jpg"].contains(output.pathExtension) { try writeCGImage(result,to:output) }
        else {
            let temporary = output.deletingLastPathComponent().appendingPathComponent("rendered-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at:temporary) }
            try writeCGImage(result,to:temporary);try image(temporary,to:output,options:OperationOptions())
        }
    }
    func hexColor(_ text:String) -> CGColor {
        let cleaned = text.trimmingCharacters(in:CharacterSet.alphanumerics.inverted); let value = UInt64(cleaned,radix:16) ?? 0xF56D29
        return CGColor(red:Double((value>>16)&255)/255,green:Double((value>>8)&255)/255,blue:Double(value&255)/255,alpha:1)
    }
    func detectRegions(_ input:URL,faces:Bool) throws -> [CGRect] {
        let handler = VNImageRequestHandler(url:input)
        if faces {
            let request = VNDetectFaceRectanglesRequest(); try handler.perform([request]); return (request.results ?? []).map { let r = $0.boundingBox; return CGRect(x:r.minX,y:1-r.maxY,width:r.width,height:r.height) }
        }
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; try handler.perform([request]); return (request.results ?? []).map { let r = $0.boundingBox; return CGRect(x:r.minX,y:1-r.maxY,width:r.width,height:r.height) }
    }
    func readQRCode(_ input:URL) throws -> String {
        let request = VNDetectBarcodesRequest(); try VNImageRequestHandler(url:input).perform([request])
        let values = request.results?.compactMap(\.payloadStringValue) ?? []
        guard !values.isEmpty else { throw ClementineError.message("No QR code or barcode was found.") }; return values.joined(separator:"\n")
    }
}
