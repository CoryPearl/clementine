import Foundation
import CoreGraphics
import ImageIO

private final class ArtworkCollector {
    var images:[CGImage] = []; var depth = 0; var walks = 0; var pixels = 0
    func walk(_ dictionary:CGPDFDictionaryRef) {
        guard depth < 10,images.count < 100,walks < 200 else { return }
        walks += 1; depth += 1; defer { depth -= 1 }
        CGPDFDictionaryApplyFunction(dictionary,{ _,object,context in
            guard let context else { return }
            let collector = Unmanaged<ArtworkCollector>.fromOpaque(context).takeUnretainedValue()
            var stream:CGPDFStreamRef?
            guard CGPDFObjectGetValue(object,.stream,&stream),let stream else { return }
            guard let dictionary = CGPDFStreamGetDictionary(stream) else { return }
            var subtype:UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dictionary,"Subtype",&subtype),let subtype else { return }
            let type = String(cString:subtype)
            if type == "Form" {
                var resources:CGPDFDictionaryRef?;var xobjects:CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(dictionary,"Resources",&resources),let resources,CGPDFDictionaryGetDictionary(resources,"XObject",&xobjects),let xobjects { collector.walk(xobjects) }
            } else if type == "Image",collector.images.count < 100 {
                if let image = collector.decode(stream,dictionary) { collector.images.append(image) }
            }
        },Unmanaged.passUnretained(self).toOpaque())
    }
    func decode(_ stream:CGPDFStreamRef,_ dict:CGPDFDictionaryRef)->CGImage? {
        var w:CGPDFInteger = 0,h:CGPDFInteger = 0,bits:CGPDFInteger = 8
        guard CGPDFDictionaryGetInteger(dict,"Width",&w),CGPDFDictionaryGetInteger(dict,"Height",&h),w >= 24,h >= 24,w < 30000,h < 30000,w*h <= 50_000_000-pixels else { return nil }
        pixels += w*h
        _ = CGPDFDictionaryGetInteger(dict,"BitsPerComponent",&bits)
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream,&format) else { return nil }
        if format != .raw {
            guard let source = CGImageSourceCreateWithData(data,nil) else { return nil }; return CGImageSourceCreateImageAtIndex(source,0,nil)
        }
        var name:UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dict,"ColorSpace",&name),let name else { return nil }
        let color = String(cString:name)
        let space:CGColorSpace
        if color == "DeviceRGB" { space = CGColorSpaceCreateDeviceRGB() }
        else if color == "DeviceGray" { space = CGColorSpaceCreateDeviceGray() }
        else if color == "DeviceCMYK" { space = CGColorSpaceCreateDeviceCMYK() }
        else { return nil }
        let components = space.numberOfComponents
        let row = (w*components*bits+7)/8
        guard CFDataGetLength(data) >= row*h,let provider = CGDataProvider(data:data) else { return nil }
        return CGImage(width:w,height:h,bitsPerComponent:bits,bitsPerPixel:bits*components,bytesPerRow:row,space:space,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.none.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)
    }
}
extension Engine {
    func pdfArtwork(_ input:URL,work:URL) throws -> [[URL]] {
        guard let document = CGPDFDocument(input as CFURL) else { return [] }
        var result:[[URL]] = []
        for n in 1...max(1,document.numberOfPages) {
            try token.check();let collector = ArtworkCollector()
            if let page = document.page(at:n),let dict = page.dictionary {
                 var resources:CGPDFDictionaryRef?,xobjects:CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(dict,"Resources",&resources),let resources,CGPDFDictionaryGetDictionary(resources,"XObject",&xobjects),let xobjects { collector.walk(xobjects) }
            }
            var images:[URL] = []
            for (i,image) in collector.images.enumerated() {
                let url = work.appendingPathComponent("page-\(n)-artwork-\(i+1).png");try writeCGImage(image,to:url);images.append(url)
            };result.append(images)
        };return result
    }
}
