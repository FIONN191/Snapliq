import AVFoundation
import ScreenCaptureKit
import AppKit

/// All mutable encoder state is confined to queue. Samples are never retained as a frame history.
final class RecordingEncoder: @unchecked Sendable {
    let queue=DispatchQueue(label:"Snapliq.RecordingEncoder",qos:.userInitiated)
    private let writer:AVAssetWriter
    private let video:AVAssetWriterInput
    private let audio:AVAssetWriterInput?
    private let mic:AVAssetWriterInput?
    let url:URL
    private var origin:CMTime?
    private var offset=CMTime.zero
    private var lastRaw=CMTime.zero
    private var lastOutput=CMTime.zero
    private var lastTrack=[Int:CMTime]()
    private var pauseStarted:CMTime?
    private var lastVideo:CMSampleBuffer?
    private var paused=false,finished=false
    private(set) var dropped=0
    private(set) var frameCount=0
    private var lastError:Error?
    var errorHandler:((Error)->Void)?
    init(url:URL,width:Int,height:Int,systemAudio:Bool,microphone:Bool)throws{
        self.url=url;writer=try AVAssetWriter(outputURL:url,fileType:.mp4)
        video=AVAssetWriterInput(mediaType:.video,outputSettings:[
            AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height,
            AVVideoColorPropertiesKey:[AVVideoColorPrimariesKey:AVVideoColorPrimaries_ITU_R_709_2,AVVideoTransferFunctionKey:AVVideoTransferFunction_ITU_R_709_2,AVVideoYCbCrMatrixKey:AVVideoYCbCrMatrix_ITU_R_709_2],
            AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:min(24_000_000,max(4_000_000,width*height*5)),AVVideoMaxKeyFrameIntervalKey:60]])
        video.expectsMediaDataInRealTime=true
        guard writer.canAdd(video) else{throw CaptureFailure.message("视频编码器不可用。")};writer.add(video)
        func audioInput()->AVAssetWriterInput {
            let i=AVAssetWriterInput(mediaType:.audio,outputSettings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:48000,AVNumberOfChannelsKey:2,AVEncoderBitRateKey:160000])
            i.expectsMediaDataInRealTime=true;return i
        }
        audio=systemAudio ? audioInput():nil;mic=microphone ? audioInput():nil
        for input in [audio,mic].compactMap({$0}) {
            guard writer.canAdd(input) else{throw CaptureFailure.message("音频编码器不可用。")};writer.add(input)
        }
        guard writer.startWriting() else{throw writer.error ?? CaptureFailure.message("无法开始写入录屏文件。")}
    }
    func setPaused(_ value:Bool,at timestamp:CMTime?=nil){
        let time=timestamp ?? CMClockGetTime(CMClockGetHostTimeClock())
        queue.async{
            if value && !self.paused{self.pauseStarted=time}
            if !value && self.paused,let start=self.pauseStarted,self.origin != nil{
                self.offset=CMTimeAdd(self.offset,CMTimeMaximum(.zero,CMTimeSubtract(time,start)))
            }
            self.paused=value
        }
    }
    /// Call only on queue, including the ScreenCaptureKit sample callbacks.
    func consume(_ sample:CMSampleBuffer,type:Int) {
        guard !finished,!paused,sample.isValid,CMSampleBufferDataIsReady(sample) else{return}
        let raw=CMSampleBufferGetPresentationTimeStamp(sample)
        guard raw.isNumeric else{return}
        if type==0 {
            if origin==nil{origin=raw;writer.startSession(atSourceTime:.zero)}
            lastRaw=raw
        }
        guard let origin=origin else{return}
        let shift=CMTimeAdd(origin,offset)
        let pts=CMTimeSubtract(raw,shift)
        guard pts >= .zero, lastTrack[type]==nil || pts>lastTrack[type]! else{return}
        let input=type==0 ? video:(type==1 ? audio:mic)
        guard let input=input else{return}
        guard input.isReadyForMoreMediaData else{dropped+=1;return}
        do {
            let adjusted=try Self.retime(sample,subtract:shift)
            guard input.append(adjusted) else{throw writer.error ?? CaptureFailure.message("录屏编码失败。")}
            lastTrack[type]=pts;lastOutput=CMTimeMaximum(lastOutput,pts)
            if type==0{frameCount+=1;lastVideo=adjusted}
        } catch {
            lastError=error;finished=true;errorHandler?(error)
        }
    }
    static func retime(_ sample:CMSampleBuffer,subtract shift:CMTime)throws->CMSampleBuffer{
        var count=0
        guard CMSampleBufferGetSampleTimingInfoArray(sample,entryCount:0,arrayToFill:nil,entriesNeededOut:&count)==noErr else{throw CaptureFailure.message("无法读取音视频时间戳。")}
        var timing=[CMSampleTimingInfo](repeating:CMSampleTimingInfo(duration:.invalid,presentationTimeStamp:.invalid,decodeTimeStamp:.invalid),count:count)
        let status=timing.withUnsafeMutableBufferPointer{CMSampleBufferGetSampleTimingInfoArray(sample,entryCount:count,arrayToFill:$0.baseAddress,entriesNeededOut:&count)}
        guard status==noErr else{throw CaptureFailure.message("无法读取时间戳。")}
        for i in timing.indices {
            if timing[i].presentationTimeStamp.isValid{timing[i].presentationTimeStamp=CMTimeSubtract(timing[i].presentationTimeStamp,shift)}
            if timing[i].decodeTimeStamp.isValid{timing[i].decodeTimeStamp=CMTimeSubtract(timing[i].decodeTimeStamp,shift)}
        }
        var result:CMSampleBuffer?
        let code=timing.withUnsafeBufferPointer{CMSampleBufferCreateCopyWithNewTiming(allocator:kCFAllocatorDefault,sampleBuffer:sample,sampleTimingEntryCount:count,sampleTimingArray:$0.baseAddress!,sampleBufferOut:&result)}
        guard code==noErr,let result=result else{throw CaptureFailure.message("音视频时间戳转换失败。")};return result
    }
    func finish(duration:Double?=nil) async throws {
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
            queue.async {
                self.finished=true
                if let error=self.lastError{self.writer.cancelWriting();continuation.resume(throwing:error);return}
                guard self.origin != nil,self.frameCount>0 else{self.writer.cancelWriting();continuation.resume(throwing:CaptureFailure.message("没有取得有效视频帧，未生成录屏。"));return}
                var end=CMTimeAdd(self.lastOutput,CMTime(value:1,timescale:30))
                if let duration=duration,duration.isFinite,duration>0 {
                    let requested=CMTime(seconds:duration,preferredTimescale:60000)
                    if let last=self.lastVideo,requested>CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(last),CMTime(value:1,timescale:30)) {
                        let until=Date().addingTimeInterval(3)
                        while !self.video.isReadyForMoreMediaData && Date()<until && self.writer.status == .writing{Thread.sleep(forTimeInterval:0.005)}
                        do {
                            let pts=CMTimeSubtract(requested,CMTime(value:1,timescale:30))
                            let shift=CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(last),pts)
                            let tail=try Self.retime(last,subtract:shift)
                            guard self.video.isReadyForMoreMediaData,self.video.append(tail) else{throw self.writer.error ?? CaptureFailure.message("无法完成录屏的最后一帧。")}
                            self.frameCount+=1;end=CMTimeMaximum(end,requested)
                        }catch{self.writer.cancelWriting();self.lastVideo=nil;continuation.resume(throwing:error);return}
                    }
                }
                self.lastVideo=nil;self.writer.endSession(atSourceTime:end)
                self.video.markAsFinished();self.audio?.markAsFinished();self.mic?.markAsFinished()
                self.writer.finishWriting {
                    if self.writer.status == .completed{continuation.resume()}
                    else{continuation.resume(throwing:self.writer.error ?? CaptureFailure.message("文件封装失败。"))}
                }
            }
        }
    }
    func cancel(){queue.sync{finished=true;lastVideo=nil;writer.cancelWriting()}}
    static func mixAudio(from source:URL,to destination:URL) async throws {
        let asset=AVURLAsset(url:source)
        let tracks=try await asset.loadTracks(withMediaType:.audio)
        guard let export=AVAssetExportSession(asset:asset,presetName:AVAssetExportPresetHighestQuality) else{throw CaptureFailure.message("无法准备混音。")}
        let mix=AVMutableAudioMix()
        mix.inputParameters=tracks.map{track in let p=AVMutableAudioMixInputParameters(track:track);p.setVolume(tracks.count>1 ? 0.7:1,at:.zero);return p}
        export.audioMix=mix;export.outputURL=destination;export.outputFileType = .mp4
        await export.export()
        guard export.status == .completed else{throw export.error ?? CaptureFailure.message("录屏音频混合失败。")}
    }
}
