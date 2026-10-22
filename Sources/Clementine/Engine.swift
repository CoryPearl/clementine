import Foundation
import Darwin
import AppKit
import PDFKit
import Vision
import ImageIO

struct Engine {
    let token: CancellationToken
    static var toolsRoot: URL {
        if let override = ProcessInfo.processInfo.environment["CLEMENTINE_TOOLS"] { return URL(fileURLWithPath: override) }
        return Bundle.main.resourceURL!.appendingPathComponent("Tools")
    }
    func tool(_ name: String) throws -> String {
        let p = Self.toolsRoot.appendingPathComponent(name).path
        guard FileManager.default.isExecutableFile(atPath:p) else { throw ClementineError.message("The bundled \(name) engine is missing. Run scripts/package.py to create the complete app.") }; return p
    }
    @discardableResult func run(_ executable: String, _ args: [String], timeout: TimeInterval = 900, directory: URL? = nil) throws -> String {
        try token.check()
        let logs = FileManager.default.temporaryDirectory.appendingPathComponent("clementine-log-\(UUID().uuidString)")
        FileManager.default.createFile(atPath:logs.path,contents:nil)
        let log = try FileHandle(forWritingTo: logs)
        defer { try? log.close(); try? FileManager.default.removeItem(at:logs) }
        let p = Process()
        if executable.hasPrefix(Self.toolsRoot.path) {
            p.executableURL = URL(fileURLWithPath:"/usr/bin/sandbox-exec")
            p.arguments = ["-p","(version 1)(allow default)(deny network-outbound (remote ip \"*:*\"))",executable] + args
        } else { p.executableURL = URL(fileURLWithPath:executable); p.arguments = args }
        p.currentDirectoryURL = directory
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        env["FONTCONFIG_FILE"] = Self.toolsRoot.appendingPathComponent("fonts.conf").path
        env["MAGICK_CONFIGURE_PATH"] = Self.toolsRoot.appendingPathComponent("ImageMagick/config").path
        env["MAGICK_CODER_MODULE_PATH"] = Self.toolsRoot.appendingPathComponent("ImageMagick/modules").path
        p.environment = env; p.standardOutput = log; p.standardError = log; p.standardInput = FileHandle.nullDevice
        try p.run(); token.attach(p)
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning {
            if token.cancelled || Date() > deadline {
                p.terminate()
                Thread.sleep(forTimeInterval:0.15)
                if p.isRunning { Darwin.kill(p.processIdentifier,SIGKILL) }
                break
            }
            Thread.sleep(forTimeInterval:0.04)
        }
        p.waitUntilExit(); token.attach(nil); try token.check()
        let data = (try? Data(contentsOf:logs)) ?? Data()
        let text = String(decoding:data,as:UTF8.self)
        guard p.terminationStatus == 0 else { throw ClementineError.message(String(text.suffix(3500)).trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "\(URL(fileURLWithPath:executable).lastPathComponent) failed (\(p.terminationStatus))." : String(text.suffix(3500))) }
        return text
    }
    func execute(_ request: ConversionRequest, progress: @escaping @Sendable (Double, String) -> Void) throws -> [URL] {
        guard !request.urls.isEmpty else { throw ClementineError.message("Choose at least one file.") }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("Clementine-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:work) }
        let o = request.options
        var staged: [(URL,URL)] = []
        let toolName = request.operation.replacingOccurrences(of:"tool:",with:"")
        let combined = ["createPDF","mergePDF","joinVideos","createCollage"].contains(toolName)
        let items = combined ? [request.urls[0]] : request.urls
        for (index, input) in items.enumerated() {
            try token.check(); progress(Double(index)/Double(items.count),"Processing \(input.lastPathComponent)")
            let folder = work.appendingPathComponent("item-\(index)",isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let generated: [URL]
            if request.operation.hasPrefix("convert:") {
                generated = try convert(input,to:String(request.operation.dropFirst(8)),options:o,work:folder)
            } else if let t = Tool(rawValue:toolName) { generated = try perform(t,input:input,all:request.urls,options:o,work:folder) }
            else { throw ClementineError.message("Unknown operation: \(request.operation)") }
            for file in generated {
                guard FileManager.default.fileExists(atPath:file.path) else { throw ClementineError.message("The engine did not create an output file.") }
                staged.append((file,o.destination ?? input.deletingLastPathComponent()))
            }
        }
        try token.check()
        var published: [URL] = []
        do {
            for (file,directory) in staged {
                try token.check()
                let output = try publish(file,to:directory)
                published.append(output)
            }
        } catch {
            for file in published { try? FileManager.default.removeItem(at:file) }
            throw error
        }
        progress(1,"Finished"); return published
    }
    func publish(_ file: URL,to directory: URL) throws -> URL {
        let manager = FileManager.default
        guard (try directory.resourceValues(forKeys:[.isDirectoryKey])).isDirectory == true else { throw ClementineError.message("Output location must be a folder.") }
        // A hidden sibling keeps cross-volume copies invisible until the final rename.
        let hidden = directory.appendingPathComponent(".clementine-\(UUID().uuidString)")
        try manager.copyItem(at:file,to:hidden)
        defer { try? manager.removeItem(at:hidden) }
        var count = 1
        while true {
            let ext = file.pathExtension
            let stem = file.deletingPathExtension().lastPathComponent
            let name = count == 1 ? file.lastPathComponent : "\(stem) \(count)" + (ext.isEmpty ? "" : ".\(ext)")
            let output = directory.appendingPathComponent(name)
            do { try manager.moveItem(at:hidden,to:output); return output }
            catch let e as NSError where e.domain == NSCocoaErrorDomain && e.code == NSFileWriteFileExistsError { count += 1 }
        }
    }
    func named(_ input:URL,_ ext:String,_ work:URL,suffix:String = "") -> URL { work.appendingPathComponent(input.deletingPathExtension().lastPathComponent + suffix).appendingPathExtension(ext) }
    func convert(_ input:URL,to ext:String,options o:OperationOptions,work:URL) throws -> [URL] {
        let output = named(input,ext,work)
        switch Registry.category(input) {
        case .image:
            if ext == "pdf" { try imagesPDF([input],to:output) }
            else { try image(input,to:output,options:o) }
        case .audio, .video:
            try media(input,to:output,options:o)
        case .pdf:
            return try pdfConvert(input,to:ext,options:o,work:work)
        case .subtitle:
            try subtitle(input,to:output)
        case .archive:
            let expanded = work.appendingPathComponent("expanded")
            try extractArchive(input,to:expanded)
            let archiveOutput = ext == "gz" ? work.appendingPathComponent(input.deletingPathExtension().lastPathComponent + ".tar.gz") : output
            let flag = ext == "zip" ? "--format=zip" : "--format=pax"
            try run("/usr/bin/tar",["-c",flag] + (ext == "gz" ? ["-z"] : []) + ["-f",archiveOutput.path,"-C",expanded.path,"."])
            return [archiveOutput]
        case .document,.ebook,.slides,.spreadsheet:
            return try office(input,to:ext,options:o,work:work)
        case .other: throw ClementineError.message("This file type has no conversion engine.")
        }
        return [output]
    }
    func image(_ input:URL,to output:URL,options o:OperationOptions,extra:[String] = []) throws {
        var source = input
        var svgRaster:URL?
        defer { if let svgRaster { try? FileManager.default.removeItem(at:svgRaster) } }
        if Registry.ext(input) == "svg" {
            let raster = output.deletingLastPathComponent().appendingPathComponent("svg-\(UUID().uuidString).png")
            try run(try tool("rsvg-convert"),["--output",raster.path,input.path]);source = raster;svgRaster = raster
        }
        var args = [source.path + (source.pathExtension.lowercased() == "gif" ? "[0]" : "")]
        args += ["-auto-orient"]
        if o.width > 0 || o.height > 0 { args += ["-resize","\(o.width > 0 ? String(o.width) : "")x\(o.height > 0 ? String(o.height) : "")"] }
        args += extra
        if output.pathExtension == "jpg" { args += ["-background","white","-alpha","remove","-alpha","off"] }
        args += ["-quality",String(Int(o.quality)),output.path]
        try run(try tool("magick"),args)
        if o.targetKB > 0 {
            var quality = Int(o.quality)
            while fileSize(output) > Int64(o.targetKB * 1024) && quality > 10 {
                quality -= 8; try token.check()
                var retry = args; if let q = retry.firstIndex(of:"-quality") { retry[q+1] = String(max(quality,10)) }
                try run(try tool("magick"),retry)
            }
            guard fileSize(output) <= Int64(o.targetKB * 1024) else { throw ClementineError.message("This image cannot reach the requested size at the selected dimensions. Try smaller dimensions or JPEG/WebP.") }
        }
    }
    func fileSize(_ u:URL) -> Int64 { ((try? FileManager.default.attributesOfItem(atPath:u.path)[.size]) as? NSNumber)?.int64Value ?? 0 }
    func ff(_ args:[String]) throws { try run(try tool("ffmpeg"),["-hide_banner","-loglevel","error","-nostdin","-y"] + args,timeout:7200) }
    func probe(_ input:URL) throws -> [String:Any] {
        let text = try run(try tool("ffprobe"),["-v","quiet","-show_format","-show_streams","-of","json",input.path])
        return (try JSONSerialization.jsonObject(with:Data(text.utf8))) as? [String:Any] ?? [:]
    }
    func duration(_ input:URL) -> Double { guard let p = try? probe(input), let f = p["format"] as? [String:Any] else { return 0 }; return Double(f["duration"] as? String ?? "0") ?? 0 }
    func codecs(_ ext:String,options o:OperationOptions) -> [String] {
        let quality = max(16,min(40,Int(42 - o.quality * 0.25)))
        switch ext {
        case "mp3": return ["-vn","-c:a","libmp3lame","-b:a","\(max(64,Int(o.quality*3.2)))k"]
        case "m4a": return ["-vn","-c:a","aac","-b:a","192k"]
        case "wav": return ["-vn","-c:a","pcm_s16le"]
        case "flac": return ["-vn","-c:a","flac"]
        case "ogg": return ["-vn","-c:a","vorbis","-strict","experimental","-ac","2","-q:a","5"]
        case "opus": return ["-vn","-c:a","libopus","-b:a","128k"]
        case "aiff": return ["-vn","-c:a","pcm_s16be"]
        case "wma": return ["-vn","-c:a","wmav2","-b:a","192k"]
        case "webm": return ["-c:v","libvpx-vp9","-crf",String(quality),"-b:v","0","-pix_fmt","yuva420p","-c:a","libopus"]
        case "wmv": return ["-c:v","wmv2","-b:v","2500k","-c:a","wmav2"]
        case "avi": return ["-c:v","mpeg4","-q:v","4","-c:a","libmp3lame"]
        case "gif": return []
        default: return ["-c:v","libx264","-preset","fast","-crf",String(quality),"-pix_fmt","yuv420p","-c:a","aac","-b:a","192k"] + (["mp4","mov"].contains(ext) ? ["-movflags","+faststart"] : [])
        }
    }
    func media(_ input:URL,to output:URL,options o:OperationOptions,videoFilters:[String] = [],audioFilters:[String] = [],extra:[String] = []) throws {
        var args: [String] = []
        if o.start > 0 { args += ["-ss",String(o.start)] }
        if o.end > o.start { args += ["-t",String(o.end-o.start)] }
        args += ["-i",input.path]
        let isVideo = Registry.category(input) == .video && !Registry.audios.contains(output.pathExtension)
        var vf = videoFilters
        if isVideo {
            if o.width > 0 || o.height > 0 { vf += ["scale=\(o.width > 0 ? String(o.width) : "-2"):\(o.height > 0 ? String(o.height) : "-2")"] }
            if output.pathExtension == "gif" { vf += ["fps=15","scale=640:-1:flags=lanczos","split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse"] }
            else { vf += ["pad=ceil(iw/2)*2:ceil(ih/2)*2"] }
        }
        if !vf.isEmpty { args += ["-vf",vf.joined(separator:",")] }
        if !audioFilters.isEmpty { args += ["-af",audioFilters.joined(separator:",")] }
        args += codecs(output.pathExtension,options:o)
        if o.targetKB > 0 {
            let d = o.end > o.start ? o.end-o.start : max(1,duration(input)-o.start)
            let kbps = Int(o.targetKB * 8 / d * 0.92)
            if isVideo { guard kbps > 64 else { throw ClementineError.message("The target size is too small for this duration.") }; args += ["-b:v","\(max(32,kbps-128))k","-maxrate","\(max(32,kbps-128))k","-bufsize","\(kbps*2)k"] }
            else { args += ["-b:a","\(max(32,kbps))k"] }
        }
        args += extra + [output.path]; try ff(args)
        if o.targetKB > 0 && fileSize(output) > Int64(o.targetKB*1024*1.05) { throw ClementineError.message("The encoded file exceeds the target size. Choose a larger target or lower the dimensions.") }
    }
    func perform(_ t:Tool,input:URL,all:[URL],options o:OperationOptions,work:URL) throws -> [URL] {
        let cat = Registry.category(input); let ext = Registry.ext(input)
        let outExt = cat == .image ? (ext == "svg" ? "png" : ext) : ext
        let output = named(input,outExt,work,suffix:" - \(t.title)")
        switch t {
        case .compress:
            if cat == .image { try image(input,to:output,options:o) }
            else if cat == .pdf { try compressPDF(input,to:output,quality:o.quality) }
            else { try media(input,to:output,options:o) }
        case .metadata:
            if o.removeMetadata && cat == .pdf { try cleanPDFMetadata(input,to:output); return [output] }
            if o.removeMetadata && (cat == .video || cat == .audio) {
                try ff(["-i",input.path,"-map","0","-map_metadata","-1","-map_chapters","-1","-c","copy",output.path]); return [output]
            }
            try FileManager.default.copyItem(at:input,to:output)
            var args = ["-overwrite_original"]
            if o.removeMetadata { args += ["-all="] }
            else {
                args += ["-Author=\(o.author)","-Title=\(o.title)"]
                let allowed = Set(["Make","Model","LensModel","Artist","Copyright","GPSLatitude","GPSLongitude","GPSLatitudeRef","GPSLongitudeRef","Software","Description"])
                for (key,value) in o.metadataTags where allowed.contains(key) && !value.isEmpty { args.append("-\(key)=\(value)") }
            }
            try run(try tool("exiftool"),args + [output.path])
        case .editImage:
            var filters = ["-evaluate","multiply",String(pow(2,o.exposure)),"-brightness-contrast","0x\((o.contrast-1)*100)","-modulate","100,\(o.saturation*100),100"]
            if o.flipHorizontal { filters += ["-flop"] }; if o.flipVertical { filters += ["-flip"] }
            if o.sharpness > 0 { filters += ["-unsharp","0x1+\(o.sharpness)+0"] }
            if o.temperature != 0 { filters += ["-fill",o.temperature > 0 ? "#FFA040" : "#4080FF","-colorize","\(abs(o.temperature)*10)"] }
            if o.vignette > 0 { filters += ["-background","black","-vignette","0x\(o.vignette*20)"] }
            if o.effect == "Grayscale" { filters += ["-colorspace","gray"] }; if o.effect == "Sepia" { filters += ["-sepia-tone","80%"] }
            filters += ["-rotate",String(o.rotation)]
            try image(input,to:output,options:o,extra:filters)
        case .cropImage:
            guard o.width > 0, o.height > 0 else { throw ClementineError.message("Enter a crop width and height.") }
            var cropOptions = o; cropOptions.width = 0; cropOptions.height = 0
            try image(input,to:output,options:cropOptions,extra:["-crop","\(o.width)x\(o.height)+\(o.cropX)+\(o.cropY)","+repage"])
        case .annotateImage,.redactImage,.frameImage:
            try renderImage(input,to:output,tool:t,options:o)
        case .createCollage:
            try run(try tool("magick"),["montage","-font","/System/Library/Fonts/Supplemental/Arial.ttf"] + all.map(\.path) + ["-auto-orient","-thumbnail","600x600>","-tile","\(Int(ceil(sqrt(Double(all.count)))))x","-geometry","+12+12","-background",o.background,output.path])
        case .createPDF: let pdf = named(input,"pdf",work,suffix:" - Combined"); try imagesPDF(all,to:pdf); return [pdf]
        case .mergePDF:
            let pdf = named(input,"pdf",work,suffix:" - Merged"); try mergePDF(all,to:pdf); return [pdf]
        case .splitPDF: return try splitPDF(input,order:o.pageOrder,groups:o.splitGroups,work:work)
        case .organizePDF: try organizePDF(input,to:output,order:o.pageOrder,rotation:o.rotation,rotations:o.pageRotations)
        case .extractArchive:
            let folder = work.appendingPathComponent(input.deletingPathExtension().lastPathComponent + " - Extracted")
            try extractArchive(input,to:folder); return [folder]
        case .normalizeAudio: try media(input,to:output,options:o,audioFilters:["loudnorm=I=-16:TP=-1.5:LRA=11"])
        case .audioChannels: try media(input,to:output,options:o,audioFilters:["volume=\(pow(10,o.gain/20))"],extra:["-ac",String(o.channels)])
        case .muteVideo: try media(input,to:output,options:o,extra:["-an"])
        case .trimVideo,.trimAudio: try media(input,to:output,options:o)
        case .cropVideo:
            guard o.width > 0, o.height > 0 else { throw ClementineError.message("Enter crop dimensions.") }
            var settings = o; settings.width = 0; settings.height = 0
            try media(input,to:output,options:settings,videoFilters:["crop=\(o.width):\(o.height):\(o.cropX):\(o.cropY)"])
        case .changeVideoSpeed:
            let rate = max(0.25,min(4,o.speed)); var factors:[Double] = []; var remaining = rate
            while remaining > 2 { factors.append(2); remaining /= 2 }; while remaining < 0.5 { factors.append(0.5); remaining /= 0.5 }; factors.append(remaining)
            let p = try probe(input); let hasAudio = (p["streams"] as? [[String:Any]] ?? []).contains { $0["codec_type"] as? String == "audio" }
            try media(input,to:output,options:o,videoFilters:["setpts=PTS/\(rate)"],audioFilters:hasAudio ? factors.map { "atempo=\($0)" } : [])
        case .splitVideo:
            let d = duration(input); let times = try parseTimes(o.splitTimes,duration:d)
            var outputs:[URL] = []; let bounds = [0.0] + times + [d]
            for i in 0..<bounds.count-1 { var settings = o; settings.start = bounds[i]; settings.end = bounds[i+1]; let part = named(input,ext,work,suffix:String(format:" - Clip %03d",i+1)); try media(input,to:part,options:settings); outputs.append(part) }; return outputs
        case .joinVideos: return [try joinVideos(all,options:o,work:work)]
        case .videoSnapshots:
            let folder = work.appendingPathComponent(input.deletingPathExtension().lastPathComponent + " - Frames"); try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let times = o.splitTimes.trimmingCharacters(in:.whitespaces).isEmpty ? [o.start] : try parseTimes(o.splitTimes,duration:duration(input),allowZero:true)
            for (i,time) in times.enumerated() { try ff(["-ss",String(time),"-i",input.path,"-frames:v","1",folder.appendingPathComponent(String(format:"Frame %03d.png",i+1)).path]) }; return [folder]
        case .audioToVideo:
            let video = named(input,"mp4",work,suffix:" - Visualization")
            let filter = o.visualizer == "Spectrum" ? "showspectrum=s=1280x720:mode=combined:color=rainbow:slide=scroll" : "showwaves=s=1280x720:mode=line:colors=0xf56d29:rate=30"
            try ff(["-i",input.path,"-filter_complex","[0:a]\(filter),format=yuv420p[v]","-map","[v]","-map","0:a","-c:v","libx264","-preset","fast","-c:a","aac","-shortest",video.path]); return [video]
        case .redactAudio:
            let ranges = try parseRanges(o.redactRanges,duration:duration(input)); guard !ranges.isEmpty else { throw ClementineError.message("Enter at least one time range, such as 1-3, 8-10.") }
            let enable = ranges.map { "between(t,\($0.0),\($0.1))" }.joined(separator:"+")
            let filter = "[0:a]volume=0:enable='\(enable)'[clean];sine=frequency=1000:sample_rate=48000,volume='if(gt(\(enable),0),0.15,0)':eval=frame,atrim=duration=\(duration(input))[tone];[clean][tone]amix=inputs=2:normalize=0[out]"
            try ff(["-i",input.path,"-filter_complex",filter,"-map","[out]"] + codecs(ext,options:o) + [output.path])
        case .redactVideo:
            guard !o.rectangles.isEmpty else { throw ClementineError.message("Draw a rectangle over the area to redact.") }
            var filters:[String] = []
            let ranges = try parseRanges(o.redactRanges,duration:duration(input)); let enable = ranges.isEmpty ? "" : ":enable='" + ranges.map { "between(t,\($0.0),\($0.1))" }.joined(separator:"+") + "'"
            for r in o.rectangles { filters.append("drawbox=x=iw*\(r.minX):y=ih*\(r.minY):w=iw*\(r.width):h=ih*\(r.height):color=black:t=fill\(enable)") }
            try media(input,to:output,options:o,videoFilters:filters)
        }
        return [output]
    }
    func parseTimes(_ text:String,duration:Double,allowZero:Bool = false) throws -> [Double] {
        let values = text.split(separator:",").map { Double($0.trimmingCharacters(in:.whitespaces)) }
        guard !values.isEmpty, values.allSatisfy({ $0 != nil && $0!.isFinite && $0! >= (allowZero ? 0 : 0.05) && $0! < duration }) else { throw ClementineError.message("Enter comma-separated seconds within the file duration.") }
        let sorted = Array(Set(values.compactMap { $0 })).sorted()
        for pair in zip(sorted,sorted.dropFirst()) where pair.1-pair.0 < 0.05 { throw ClementineError.message("Split points must be at least 0.05 seconds apart.") }
        return sorted
    }
    func parseRanges(_ text:String,duration:Double) throws -> [(Double,Double)] {
        if text.trimmingCharacters(in:.whitespaces).isEmpty { return [] }
        return try text.split(separator:",").map { piece in
            let v = piece.split(separator:"-").map { Double($0.trimmingCharacters(in:.whitespaces)) }
            guard v.count == 2, let a = v[0], let b = v[1], a.isFinite, b.isFinite, a >= 0, b > a, b <= duration else { throw ClementineError.message("Time ranges must be inside the file, such as 1-3, 8-10.") }; return (a,b)
        }
    }
    func joinVideos(_ inputs:[URL],options o:OperationOptions,work:URL) throws -> URL {
        var args:[String] = []; var filters:[String] = []; var pads = ""
        for (i,input) in inputs.enumerated() {
            args += ["-i",input.path]; let info = try probe(input); let streams = info["streams"] as? [[String:Any]] ?? []
            filters.append("[\(i):v]scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30,setpts=PTS-STARTPTS[v\(i)]")
            if streams.contains(where:{ $0["codec_type"] as? String == "audio" }) { filters.append("[\(i):a]aresample=48000,aformat=channel_layouts=stereo,asetpts=PTS-STARTPTS[a\(i)]") }
            else { filters.append("anullsrc=r=48000:cl=stereo,atrim=duration=\(duration(input))[a\(i)]") }
            pads += "[v\(i)][a\(i)]"
        }
        filters.append(pads + "concat=n=\(inputs.count):v=1:a=1[v][a]")
        let output = named(inputs[0],"mp4",work,suffix:" - Joined")
        try ff(args + ["-filter_complex",filters.joined(separator:";"),"-map","[v]","-map","[a]"] + codecs("mp4",options:o) + [output.path]); return output
    }
}
