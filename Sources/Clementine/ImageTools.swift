import Foundation
import AppKit
import CoreGraphics
import CoreImage
import CoreText
import Vision

extension Engine {
    func renderImage(_ input:URL,to output:URL,tool t:Tool,options o:OperationOptions) throws {
        var source = input
        if Registry.ext(input) == "svg" || NSImage(contentsOf:input) == nil {
            source = output.deletingLastPathComponent().appendingPathComponent("render-source.png")
            try image(input,to:source,options:OperationOptions())
        }
        guard let ns = NSImage(contentsOf:source), let cg = ns.cgImage(forProposedRect:nil,context:nil,hints:nil) else { throw ClementineError.message("Cannot open the image.") }
        var w = cg.width, h = cg.height
        if t == .frameImage {
            w += max(0,o.padding)*2; h += max(0,o.padding)*2
            let ratio:Double? = ["Square":1,"Landscape":16.0/9,"Portrait":9.0/16,"4:3":4.0/3][o.aspect]
            if let ratio { if Double(w)/Double(h) < ratio { w = Int(Double(h)*ratio) } else { h = Int(Double(w)/ratio) } }
        }
        guard w <= 30000,h <= 30000,Int64(w)*Int64(h) <= 150_000_000,let ctx = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ClementineError.message("Image dimensions are too large.") }
        if t == .frameImage {
            let c = hexColor(o.background)
            ctx.setFillColor(c); ctx.fill(CGRect(x:0,y:0,width:w,height:h))
            if o.gradient, let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[c,hexColor(o.secondaryBackground)] as CFArray,locations:[0,1]) {
                ctx.drawLinearGradient(gradient,start:.zero,end:CGPoint(x:w,y:h),options:[])
            }
            if !o.backgroundImage.isEmpty, let bg = NSImage(contentsOfFile:o.backgroundImage)?.cgImage(forProposedRect:nil,context:nil,hints:nil) { ctx.draw(bg,in:CGRect(x:0,y:0,width:w,height:h)) }
            let rect = CGRect(x:(w-cg.width)/2,y:(h-cg.height)/2,width:cg.width,height:cg.height)
            ctx.saveGState(); ctx.addPath(CGPath(roundedRect:rect,cornerWidth:o.radius,cornerHeight:o.radius,transform:nil)); ctx.clip(); ctx.draw(cg,in:rect); ctx.restoreGState()
        } else {
            ctx.draw(cg,in:CGRect(x:0,y:0,width:w,height:h))
            if t == .redactImage && o.rectangles.isEmpty { throw ClementineError.message("Draw an area to redact, or detect faces or text first.") }
            let rectangles = o.rectangles.isEmpty ? [CGRect(x:0.1,y:0.1,width:0.8,height:0.15)] : o.rectangles
            for (i,r) in rectangles.enumerated() {
                let rect = CGRect(x:r.minX*Double(w),y:(1-r.maxY)*Double(h),width:r.width*Double(w),height:r.height*Double(h))
                if t == .redactImage {
                    if o.blur {
                        let ci = CIImage(cgImage:cg).clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:30])
                        if let blurred = CIContext().createCGImage(ci,from:rect) { ctx.draw(blurred,in:rect) }
                    } else { ctx.setFillColor(CGColor(gray:0,alpha:1)); ctx.fill(rect) }
                } else {
                    ctx.setStrokeColor(hexColor(o.background)); ctx.setFillColor(hexColor(o.background)); ctx.setLineWidth(max(3,Double(w)/200))
                    switch o.annotationStyle {
                    case "Rectangle": ctx.stroke(rect)
                    case "Ellipse": ctx.strokeEllipse(in:rect)
                    case "Arrow":
                        ctx.move(to:CGPoint(x:rect.minX,y:rect.minY)); ctx.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY)); ctx.strokePath()
                        let angle = atan2(rect.height,rect.width); let len = max(15,Double(w)/40)
                        ctx.move(to:CGPoint(x:rect.maxX-len*cos(angle-0.5),y:rect.maxY-len*sin(angle-0.5))); ctx.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY)); ctx.addLine(to:CGPoint(x:rect.maxX-len*cos(angle+0.5),y:rect.maxY-len*sin(angle+0.5))); ctx.strokePath()
                    default:
                        let text = o.annotationStyle == "Number" ? "\(i+1)" : o.annotation
                        let attrs:[NSAttributedString.Key:Any] = [.font:CTFontCreateWithName("Helvetica-Bold" as CFString,o.annotationSize,nil),.foregroundColor:hexColor(o.background)]
                        let str = NSAttributedString(string:text,attributes:attrs); let line = CTLineCreateWithAttributedString(str)
                        ctx.textPosition = CGPoint(x:rect.minX,y:rect.minY+max(0,rect.height-o.annotationSize)); CTLineDraw(line,ctx)
                    }
                }
            }
        }
        guard let result = ctx.makeImage() else { throw ClementineError.message("Could not render the image.") }
        if ["png","jpg"].contains(output.pathExtension) { try writeCGImage(result,to:output) }
        else { let temp = output.deletingLastPathComponent().appendingPathComponent("rendered.png"); try writeCGImage(result,to:temp); try image(temp,to:output,options:OperationOptions()) }
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
