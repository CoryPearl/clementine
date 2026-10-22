import AppKit
import CoreImage
import CoreText
import ImageIO
import Vision

/// One rendering pipeline drives the live canvas and the full-resolution export.
enum ImageRendering {
    static let context = CIContext(options:[.cacheIntermediates:false])
    static let colorSpace = CGColorSpace(name:CGColorSpace.sRGB)!

    static func load(_ url:URL, maximumDimension:Int = 30000) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,
                kCGImageSourceThumbnailMaxPixelSize:maximumDimension,
                kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else {
            throw ClementineError.message("Cannot open this image.")
        }
        return image
    }
    static func dimensions(_ url:URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,nil),
              let p = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int,let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = p[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width:h,height:w) : CGSize(width:w,height:h)
    }
    static func cgImage(_ image:CIImage) throws -> CGImage {
        guard !image.extent.isInfinite,!image.extent.isEmpty,
              let result = context.createCGImage(image,from:image.extent.integral,format:.RGBA8,colorSpace:colorSpace) else {
            throw ClementineError.message("Could not render this image.")
        }
        return result
    }
    static func resized(_ image:CGImage,maximumDimension:Int) throws -> CGImage {
        let scale = min(1,Double(maximumDimension)/Double(max(image.width,image.height)))
        if scale == 1 { return image }
        return try cgImage(CIImage(cgImage:image).applyingFilter("CILanczosScaleTransform",parameters:[kCIInputScaleKey:scale,kCIInputAspectRatioKey:1]))
    }
    static func adjusted(_ source:CIImage,options o:OperationOptions) -> CIImage {
        var image = source.applyingFilter("CIExposureAdjust",parameters:[kCIInputEVKey:o.exposure])
            .applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:o.saturation,kCIInputContrastKey:o.contrast])
        if o.temperature != 0 {
            image = image.applyingFilter("CITemperatureAndTint",parameters:["inputNeutral":CIVector(x:6500,y:0),"inputTargetNeutral":CIVector(x:6500-o.temperature*2500,y:0)])
        }
        if o.sharpness > 0 { image = image.applyingFilter("CISharpenLuminance",parameters:[kCIInputSharpnessKey:o.sharpness]) }
        if o.vignette > 0 { image = image.applyingFilter("CIVignette",parameters:[kCIInputIntensityKey:o.vignette*2,kCIInputRadiusKey:min(image.extent.width,image.extent.height)*0.55]) }
        if o.effect == "Grayscale" { image = image.applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0]) }
        if o.effect == "Sepia" { image = image.applyingFilter("CISepiaTone",parameters:[kCIInputIntensityKey:0.8]) }
        if o.flipHorizontal { image = image.transformed(by:CGAffineTransform(scaleX:-1,y:1)) }
        if o.flipVertical { image = image.transformed(by:CGAffineTransform(scaleX:1,y:-1)) }
        if o.rotation != 0 { image = image.transformed(by:CGAffineTransform(rotationAngle:-o.rotation * .pi/180)) }
        return image.transformed(by:CGAffineTransform(translationX:-image.extent.minX,y:-image.extent.minY))
    }
    static func render(_ source:CGImage,tool:Tool,options o:OperationOptions) throws -> CGImage {
        if tool == .editImage { return try cgImage(adjusted(CIImage(cgImage:source),options:o)) }
        if tool == .cropImage {
            let rect = CropGeometry.pixelRect(options:o,size:CGSize(width:source.width,height:source.height))
            guard let cropped = source.cropping(to:rect) else { throw ClementineError.message("Choose a crop inside the image.") }
            return cropped
        }
        if ![.frameImage,.annotateImage,.redactImage].contains(tool) { return source }
        var w = source.width,h = source.height
        if tool == .frameImage {
            w += max(0,o.padding)*2; h += max(0,o.padding)*2
            if let ratio = ["Square":1.0,"Landscape":16.0/9,"Portrait":9.0/16,"4:3":4.0/3][o.aspect] {
                if Double(w)/Double(h) < ratio { w = Int(ceil(Double(h)*ratio)) }
                else { h = Int(ceil(Double(w)/ratio)) }
            }
        }
        guard w > 0,h > 0,w <= 30000,h <= 30000,Int64(w)*Int64(h) <= 150_000_000,
              let ctx = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ClementineError.message("Image dimensions are too large.")
        }
        let engine = Engine(token:CancellationToken())
        if tool == .frameImage {
            let c = engine.hexColor(o.background)
            ctx.setFillColor(c);ctx.fill(CGRect(x:0,y:0,width:w,height:h))
            if o.gradient,let gradient = CGGradient(colorsSpace:colorSpace,colors:[c,engine.hexColor(o.secondaryBackground)] as CFArray,locations:[0,1]) {
                ctx.drawLinearGradient(gradient,start:.zero,end:CGPoint(x:w,y:h),options:[])
            }
            if !o.backgroundImage.isEmpty,let background = try? load(URL(fileURLWithPath:o.backgroundImage),maximumDimension:max(w,h)) { ctx.draw(background,in:CGRect(x:0,y:0,width:w,height:h)) }
            let rect = CGRect(x:(w-source.width)/2,y:(h-source.height)/2,width:source.width,height:source.height)
            ctx.saveGState();ctx.addPath(CGPath(roundedRect:rect,cornerWidth:max(0,o.radius),cornerHeight:max(0,o.radius),transform:nil));ctx.clip();ctx.draw(source,in:rect);ctx.restoreGState()
        } else {
            ctx.draw(source,in:CGRect(x:0,y:0,width:w,height:h))
            // An empty drawing is deliberately unchanged. The live canvas never invents an annotation.
            for (i,r) in o.rectangles.enumerated() {
                let r = CropGeometry.clamped(r,minimum:CGSize(width:0.0001,height:0.0001))
                let rect = CGRect(x:r.minX*Double(w),y:(1-r.maxY)*Double(h),width:r.width*Double(w),height:r.height*Double(h))
                if tool == .redactImage {
                    if o.blur {
                        let blurred = CIImage(cgImage:source).clampedToExtent().applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:max(2,Double(w)/50)]).cropped(to:rect)
                        ctx.draw(try cgImage(blurred),in:rect)
                    } else { ctx.setFillColor(CGColor(gray:0,alpha:1));ctx.fill(rect) }
                } else {
                    ctx.setStrokeColor(engine.hexColor(o.background));ctx.setFillColor(engine.hexColor(o.background));ctx.setLineWidth(max(2,Double(w)/200))
                    switch o.annotationStyle {
                    case "Rectangle":ctx.stroke(rect)
                    case "Ellipse":ctx.strokeEllipse(in:rect)
                    case "Arrow":
                        ctx.move(to:CGPoint(x:rect.minX,y:rect.minY));ctx.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY));ctx.strokePath()
                        let angle = atan2(rect.height,rect.width),length = max(8,Double(w)/40)
                        ctx.move(to:CGPoint(x:rect.maxX-length*cos(angle-0.5),y:rect.maxY-length*sin(angle-0.5)));ctx.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY));ctx.addLine(to:CGPoint(x:rect.maxX-length*cos(angle+0.5),y:rect.maxY-length*sin(angle+0.5)));ctx.strokePath()
                    default:
                        let text = o.annotationStyle == "Number" ? "\(i+1)" : o.annotation
                        let attributes:[NSAttributedString.Key:Any] = [.font:CTFontCreateWithName("Helvetica-Bold" as CFString,max(1,o.annotationSize),nil),.foregroundColor:engine.hexColor(o.background)]
                        ctx.textPosition = CGPoint(x:rect.minX,y:rect.minY+max(0,rect.height-o.annotationSize))
                        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:attributes)),ctx)
                    }
                }
            }
        }
        guard let image = ctx.makeImage() else { throw ClementineError.message("Could not render this image.") }
        return image
    }
    static func workingOptions(_ o:OperationOptions,sourceSize:CGSize,workingSize:CGSize) -> OperationOptions {
        var result = o
        let scale = workingSize.width/max(1,sourceSize.width)
        result.padding = Int((Double(o.padding)*scale).rounded());result.radius *= scale;result.annotationSize *= scale
        result.cropX = Int((Double(o.cropX)*scale).rounded());result.cropY = Int((Double(o.cropY)*scale).rounded())
        result.width = Int((Double(o.width)*scale).rounded());result.height = Int((Double(o.height)*scale).rounded())
        return result
    }
    static func removeBackground(_ source:CGImage) throws -> CGImage {
        if #available(macOS 14.0,*) {
            let handler = VNImageRequestHandler(cgImage:source)
            let request = VNGenerateForegroundInstanceMaskRequest()
            try handler.perform([request])
            guard let observation = request.results?.first,!observation.allInstances.isEmpty else {
                throw ClementineError.message("No foreground subject was found. Try a photo with a clear person or object.")
            }
            let buffer = try observation.generateMaskedImage(ofInstances:observation.allInstances,from:handler,croppedToInstancesExtent:false)
            return try cgImage(CIImage(cvPixelBuffer:buffer))
        }
        throw ClementineError.message("Background removal needs macOS 14 or later.")
    }
}
