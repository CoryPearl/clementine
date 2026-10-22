import AVFoundation
import MediaToolbox
import CoreImage
import SwiftUI

enum LiveVideoRendering {
    static func frame(_ source:CIImage,tool:Tool,options:OperationOptions,time:Double) -> CIImage {
        var image = source
        if tool == .redactVideo {
            let ranges = (try? Engine(token:CancellationToken()).parseRanges(options.redactRanges,duration:Double.greatestFiniteMagnitude)) ?? []
            if ranges.isEmpty || ranges.contains(where:{ time >= $0.0 && time <= $0.1 }) {
                for r in options.rectangles {
                    let rect = CGRect(x:source.extent.minX+r.minX*source.extent.width,y:source.extent.minY+(1-r.maxY)*source.extent.height,width:r.width*source.extent.width,height:r.height*source.extent.height)
                    image = CIImage(color:.black).cropped(to:rect).composited(over:image)
                }
            }
        }
        if tool == .compress,options.width > 0 || options.height > 0 {
            let size = outputSize(source:source.extent.size,options:options)
            image = image.transformed(by:CGAffineTransform(scaleX:size.width/source.extent.width,y:size.height/source.extent.height))
        }
        return image
    }
    static func outputSize(source:CGSize,options:OperationOptions) -> CGSize {
        var width = CGFloat(options.width),height = CGFloat(options.height)
        if width <= 0 && height <= 0 { return source }
        if width <= 0 { width = height*source.width/max(1,source.height) }
        if height <= 0 { height = width*source.height/max(1,source.width) }
        return CGSize(width:max(2,(width/2).rounded()*2),height:max(2,(height/2).rounded()*2))
    }
}

final class LiveVideoState:@unchecked Sendable {
    private let lock = NSLock();private var value = OperationOptions()
    func update(_ options:OperationOptions) { lock.lock();value = options;lock.unlock() }
    var options:OperationOptions { lock.lock();defer { lock.unlock() };return value }
}

/// Audio is processed during playback, without rendering an eight-second file.
final class LiveAudioState:@unchecked Sendable {
    private let lock = NSLock()
    private var gain:Float = 1,mono = false,ranges:[(Double,Double)] = []
    private var samples = [Float](repeating:0,count:256)
    var sampleRate = 48000.0;var floatPCM = false;var interleaved = false

    func update(tool:Tool,options:OperationOptions,normalizationGain:Double = 1,duration:Double) {
        let nextRanges = tool == .redactAudio ? (try? Engine(token:CancellationToken()).parseRanges(options.redactRanges,duration:duration)) ?? [] : []
        lock.lock();defer { lock.unlock() }
        gain = tool == .audioChannels ? Float(pow(10,options.gain/20)) : (tool == .normalizeAudio ? Float(normalizationGain) : 1)
        mono = tool == .audioChannels && options.channels == 1;ranges = nextRanges
    }
    func waveform() -> [Float] { lock.lock();defer { lock.unlock() };return samples }
    func apply(_ buffers:UnsafeMutablePointer<AudioBufferList>,frames:Int,start:Double) {
        guard floatPCM,frames > 0 else { return }
        let list = UnsafeMutableAudioBufferListPointer(buffers)
        lock.lock();let gain = gain,mono = mono,ranges = ranges;lock.unlock()
        let channelCount = list.reduce(0) { $0+Int($1.mNumberChannels) }
        guard channelCount > 0 else { return }
        for frame in 0..<frames {
            let time = start+Double(frame)/sampleRate
            let bleep = ranges.contains { time >= $0.0 && time <= $0.1 }
            var average:Float = 0
            if mono {
                for buffer in list {
                    guard let data = buffer.mData?.assumingMemoryBound(to:Float.self) else { continue }
                    let channels = Int(buffer.mNumberChannels)
                    for channel in 0..<channels { average += data[frame*channels+channel]/Float(channelCount) }
                }
            }
            for buffer in list {
                guard let data = buffer.mData?.assumingMemoryBound(to:Float.self) else { continue }
                let channels = Int(buffer.mNumberChannels)
                for channel in 0..<channels {
                    let index = frame*channels+channel
                    data[index] = bleep ? Float(sin(2 * .pi * 1000 * time))*0.01875 : max(-1,min(1,(mono ? average : data[index])*gain))
                }
            }
        }
        if let first = list.first,let data = first.mData?.assumingMemoryBound(to:Float.self) {
            let stride = Int(first.mNumberChannels)
            lock.lock()
            for n in 0..<samples.count { samples[n] = data[min(frames-1,n*frames/samples.count)*stride] }
            lock.unlock()
        }
    }
    func makeMix(track:AVAssetTrack) throws -> AVAudioMix {
        let retained = Unmanaged.passRetained(self)
        let initialize:MTAudioProcessingTapInitCallback = { _,info,storage in storage.pointee = info }
        let finalize:MTAudioProcessingTapFinalizeCallback = { tap in
            Unmanaged<LiveAudioState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
        }
        let prepare:MTAudioProcessingTapPrepareCallback = { tap,_,format in
            let state = Unmanaged<LiveAudioState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
            state.sampleRate = format.pointee.mSampleRate
            state.floatPCM = format.pointee.mFormatID == kAudioFormatLinearPCM && format.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.pointee.mBitsPerChannel == 32
        }
        let process:MTAudioProcessingTapProcessCallback = { tap,count,_,buffers,frames,flags in
            var time = CMTimeRange.zero
            let status = MTAudioProcessingTapGetSourceAudio(tap,count,buffers,flags,&time,frames)
            guard status == noErr else { frames.pointee = 0;return }
            let state = Unmanaged<LiveAudioState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
            state.apply(buffers,frames:frames.pointee,start:time.start.seconds.isFinite ? time.start.seconds : 0)
        }
        var callbacks = MTAudioProcessingTapCallbacks(version:kMTAudioProcessingTapCallbacksVersion_0,clientInfo:retained.toOpaque(),init:initialize,finalize:finalize,prepare:prepare,unprepare:nil,process:process)
        var tap:MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault,&callbacks,kMTAudioProcessingTapCreationFlag_PostEffects,&tap)
        guard status == noErr,let tap else { retained.release();throw ClementineError.message("Could not initialize live audio (\(status)).") }
        let parameters = AVMutableAudioMixInputParameters(track:track);parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix();mix.inputParameters = [parameters];return mix
    }
}

struct LiveVisualizer:View {
    let state:LiveAudioState;let spectrum:Bool
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/30)) { _ in
            Canvas { context,size in draw(context:&context,size:size) }
        }.padding(24).background(orange.opacity(0.05)).accessibilityLabel(spectrum ? "Live audio spectrum" : "Live audio waveform")
    }
    private func draw(context:inout GraphicsContext,size:CGSize) {
        let samples = state.waveform()
        if spectrum {
            let count = 40
            let width = size.width/CGFloat(count)
            for bin in 1...count {
                var real = 0.0,imaginary = 0.0
                for n in 0..<samples.count {
                    let angle = 2 * Double.pi * Double(bin*n)/Double(samples.count)
                    real += Double(samples[n])*cos(angle);imaginary += Double(samples[n])*sin(angle)
                }
                let level = min(1,sqrt(real*real+imaginary*imaginary)/Double(samples.count)*8)
                let height = max(CGFloat(2),size.height*CGFloat(level))
                let rect = CGRect(x:CGFloat(bin-1)*width+1,y:size.height-height,width:width-2,height:height)
                context.fill(Path(roundedRect:rect,cornerRadius:3),with:.color(orange))
            }
        } else {
            var path = Path()
            for (n,value) in samples.enumerated() {
                let point = CGPoint(x:CGFloat(n)/CGFloat(samples.count-1)*size.width,y:size.height/2-CGFloat(value)*size.height*0.45)
                if n == 0 { path.move(to:point) } else { path.addLine(to:point) }
            }
            context.stroke(path,with:.color(orange),lineWidth:2)
        }
    }
}
