import Foundation
import AppKit
import UniformTypeIdentifiers

let accent = NSColor(calibratedRed: 0.96, green: 0.43, blue: 0.16, alpha: 1)

enum Category: String, CaseIterable, Codable {
    case image, audio, video, pdf, document, slides, spreadsheet, ebook, subtitle, archive, other
    var symbol: String { switch self {
    case .image: return "photo"; case .audio: return "waveform"; case .video: return "film"; case .pdf: return "doc.richtext"
    case .document: return "doc.text"; case .slides: return "rectangle.on.rectangle"; case .spreadsheet: return "tablecells"
    case .ebook: return "book.closed"; case .subtitle: return "captions.bubble"; case .archive: return "archivebox"; case .other: return "doc"
    }}
    var title: String { rawValue.capitalized }
}
struct FileSelection {
    var urls: [URL]
    var category: Category { Set(urls.map { Registry.category($0) }).count == 1 ? Registry.category(urls[0]) : .other }
    var label: String { urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files" }
}
enum WheelMode: String, CaseIterable { case convert = "Convert", tools = "Tools", actions = "Actions" }
struct OperationDescriptor: Identifiable, Hashable {
    var id: String; var title: String; var symbol: String; var detail: String = ""; var needsEditor = false
}
enum Tool: String, CaseIterable {
    case compress, metadata, editImage, annotateImage, frameImage, cropImage, normalizeAudio, muteVideo, trimVideo, splitPDF, organizePDF, extractArchive, createPDF, mergePDF, cropVideo, changeVideoSpeed, joinVideos, videoSnapshots, splitVideo, audioToVideo, trimAudio, audioChannels, createCollage, redactImage, redactVideo, redactAudio
    var title: String { switch self {
    case .compress: return "Compress"; case .metadata: return "Metadata"; case .editImage: return "Edit Photo"; case .annotateImage: return "Annotate Photo"
    case .frameImage: return "Add Background"; case .cropImage: return "Crop Image"; case .normalizeAudio: return "Normalize Volume"; case .muteVideo: return "Remove Audio"
    case .trimVideo: return "Trim Video"; case .splitPDF: return "Split PDF"; case .organizePDF: return "Organize PDF"; case .extractArchive: return "Extract Archive"
    case .createPDF: return "Create PDF"; case .mergePDF: return "Merge PDFs"; case .cropVideo: return "Crop Video"; case .changeVideoSpeed: return "Change Speed"
    case .joinVideos: return "Join Videos"; case .videoSnapshots: return "Video Snapshots"; case .splitVideo: return "Split Video"; case .audioToVideo: return "Audio Visualizer"
    case .trimAudio: return "Trim Audio"; case .audioChannels: return "Audio Channels"; case .createCollage: return "Create Collage"; case .redactImage: return "Redact Photo"
    case .redactVideo: return "Redact Video"; case .redactAudio: return "Bleep Audio"
    }}
    var symbol: String { switch self {
    case .compress: return "arrow.down.right.and.arrow.up.left"; case .metadata: return "tag"; case .editImage: return "slider.horizontal.3"
    case .annotateImage: return "pencil.tip.crop.circle"; case .frameImage: return "photo.artframe"; case .cropImage, .cropVideo: return "crop"
    case .normalizeAudio: return "waveform"; case .muteVideo: return "speaker.slash"; case .trimVideo, .trimAudio: return "scissors"
    case .splitPDF, .splitVideo: return "rectangle.split.2x1"; case .organizePDF: return "square.grid.2x2"; case .extractArchive: return "archivebox"
    case .createPDF: return "doc.badge.plus"; case .mergePDF: return "doc.on.doc"; case .changeVideoSpeed: return "speedometer"; case .joinVideos: return "film.stack"
    case .videoSnapshots: return "camera"; case .audioToVideo: return "waveform.path"; case .audioChannels: return "hifispeaker.2"
    case .createCollage: return "rectangle.3.group"; case .redactImage, .redactVideo: return "eye.slash"; case .redactAudio: return "waveform.badge.minus"
    }}
    var descriptor: OperationDescriptor { .init(id: "tool:\(rawValue)", title: title, symbol: symbol, needsEditor: ![.muteVideo, .extractArchive, .createPDF, .mergePDF, .joinVideos, .createCollage].contains(self)) }
}
enum Registry {
    static let images = ["jpg", "png", "webp", "heic", "tiff", "avif", "bmp", "svg"]
    static let audios = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"]
    static let videos = ["mp4", "mov", "mkv", "webm", "avi", "wmv"]
    static let documents = ["docx", "pages", "md", "rtf", "rtfd", "textclipping", "txt", "html"]
    static let sheets = ["xlsx", "xls", "ods", "csv", "tsv"]
    static let archives = ["zip", "tar", "gz", "rar"]
    static func ext(_ u: URL) -> String { let e = u.pathExtension.lowercased(); return ["jpeg":"jpg", "tif":"tiff", "aif":"aiff", "markdown":"md", "tgz":"gz", "htm":"html" ][e] ?? e }
    static func category(_ u: URL) -> Category {
        var directory:ObjCBool = false
        if FileManager.default.fileExists(atPath:u.path,isDirectory:&directory),directory.boolValue,!Set(["pages","numbers","key","rtfd"]).contains(ext(u)) { return .other }
        return category(ext(u))
    }
    static func category(_ e: String) -> Category {
        if images.contains(e) { return .image }; if audios.contains(e) { return .audio }; if videos.contains(e) || e == "gif" { return .video }
        if e == "pdf" { return .pdf }; if documents.contains(e) { return .document }; if ["ppt", "pptx", "key"].contains(e) { return .slides }
        if sheets.contains(e) || e == "numbers" { return .spreadsheet }; if e == "epub" { return .ebook }; if ["srt", "vtt"].contains(e) { return .subtitle }
        if archives.contains(e) { return .archive }; return .other
    }
    static func outputs(_ e: String) -> [String] {
        var result: [String] = []
        switch category(e) {
        case .image: result = images.filter { $0 != "svg" } + ["pdf"]
        case .audio: result = audios
        case .video: result = e == "gif" ? videos : videos + ["gif", "mp3"]
        case .pdf: result = ["docx", "pages", "pptx", "xlsx", "jpg", "png", "epub", "txt", "md"]
        case .document: result = ["docx", "pages", "pdf", "txt", "md", "html", "epub", "png", "jpg"]
        case .slides: result = ["pdf", "jpg", "png"]
        case .spreadsheet: result = ["xlsx", "ods", "csv", "tsv", "pdf"]
        case .ebook: result = ["pdf", "docx", "pages", "txt", "md", "html"]
        case .subtitle: result = ["srt", "vtt", "txt"]
        case .archive: result = ["zip", "tar", "gz"]
        case .other: break
        }
        return result.filter { $0 != e }
    }
    static func tools(_ selection: FileSelection) -> [Tool] {
        guard !selection.urls.isEmpty else { return [] }
        switch selection.category {
        case .image: return [.compress, .metadata, .editImage, .annotateImage, .frameImage, .cropImage, .redactImage, .createPDF] + (selection.urls.count > 1 ? [.createCollage] : [])
        case .audio: return [.compress, .metadata, .normalizeAudio, .trimAudio, .audioChannels, .redactAudio, .audioToVideo]
        case .video: return [.compress, .metadata, .trimVideo, .splitVideo, .cropVideo, .changeVideoSpeed, .muteVideo, .videoSnapshots, .redactVideo] + (selection.urls.count > 1 ? [.joinVideos] : [])
        case .pdf: return [.compress, .metadata, .splitPDF, .organizePDF] + (selection.urls.count > 1 ? [.mergePDF] : [])
        case .archive: return [.extractArchive]
        default: return []
        }
    }
    static let actions: [OperationDescriptor] = [
        .init(id:"action:airdrop",title:"AirDrop",symbol:"airplayaudio"), .init(id:"action:float",title:"Float",symbol:"rectangle.on.rectangle.angled"),
        .init(id:"action:copy",title:"Copy",symbol:"doc.on.doc"), .init(id:"action:move",title:"Move",symbol:"folder"),
        .init(id:"action:path",title:"Copy Path",symbol:"link"), .init(id:"action:terminal",title:"Terminal",symbol:"terminal")]
    static func operations(_ mode: WheelMode, _ selection: FileSelection) -> [OperationDescriptor] {
        guard !selection.urls.isEmpty else { return [] }
        if mode == .actions { return actions }
        if mode == .tools { return tools(selection).map(\.descriptor) }
        let common = selection.urls.map { category($0) == .other ? [] : outputs(ext($0)) }.reduce(nil as Set<String>?) { acc, a in acc.map { $0.intersection(a) } ?? Set(a) } ?? []
        return common.sorted().map { .init(id:"convert:\($0)",title:$0 == "gz" ? "GZIP" : $0.uppercased(),symbol:category($0).symbol,detail:"Convert to \($0.uppercased())") }
    }
}
struct OperationOptions: Sendable {
    var quality = 82.0; var targetKB = 0.0; var width = 0; var height = 0; var cropX = 0; var cropY = 0
    var start = 0.0; var end = 0.0; var speed = 1.0; var channels = 2; var gain = 0.0
    var exposure = 0.0; var saturation = 1.0; var contrast = 1.0; var rotation = 0.0
    var temperature = 0.0; var sharpness = 0.0; var vignette = 0.0; var effect = "None"; var flipHorizontal = false; var flipVertical = false
    var gradient = false; var secondaryBackground = "#F7B675"; var metadataTags: [String:String] = [:]
    var padding = 60; var radius = 24.0; var background = "#F4E7D8"; var backgroundImage = ""; var aspect = "Original"
    var annotation = ""; var annotationStyle = "Text"; var annotationSize = 42.0
    var rectangles: [CGRect] = []; var blur = false; var redactRanges = ""; var splitTimes = ""; var pageOrder = ""; var splitGroups = false; var pageRotations: [Int:Int] = [:]
    var author = ""; var title = ""; var removeMetadata = true; var visualizer = "Waveform"
    var destination: URL?
}
struct ConversionRequest: Sendable { var urls: [URL]; var operation: String; var options: OperationOptions }
enum JobState: String { case queued, running, completed, failed, cancelled }
@MainActor final class Job: ObservableObject, Identifiable {
    let id = UUID(); let name: String; let operation: String
    @Published var state: JobState = .queued; @Published var message = "Waiting"; @Published var outputs: [URL] = []; @Published var progress = 0.0
    let token = CancellationToken()
    init(name: String, operation: String) { self.name = name; self.operation = operation }
}
final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock(); private var stopped = false; private var process: Process?
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func attach(_ p: Process?) { lock.lock(); process = p; let stop = stopped; lock.unlock(); if stop, let p, p.isRunning { p.terminate() } }
    func cancel() { lock.lock(); stopped = true; let p = process; lock.unlock(); if let p, p.isRunning { p.terminate() } }
    func check() throws { if cancelled { throw CancellationError() } }
}
enum ClementineError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}
