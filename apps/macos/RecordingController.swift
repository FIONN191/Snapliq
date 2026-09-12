import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreAudio

enum RecordingState:String {case idle,preparing,recording,paused,finishing}
/// Each sample sink retains its encoder for the whole stream lifetime; callbacks never read controller state.
private final class RecordingOutput:NSObject,SCStreamOutput {
    let encoder:RecordingEncoder
    init(_ encoder:RecordingEncoder){self.encoder=encoder}
    func stream(_ stream:SCStream,didOutputSampleBuffer sample:CMSampleBuffer,of type:SCStreamOutputType){
        if type == .screen {
            guard let attachments=CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:false) as? [[SCStreamFrameInfo:Any]],
                  let raw=attachments.first?[.status] as? Int,SCFrameStatus(rawValue:raw) == .complete else{return}
            encoder.consume(sample,type:0)
        } else if type == .audio {encoder.consume(sample,type:1)}
        else if #available(macOS 15.0,*),type == .microphone{encoder.consume(sample,type:2)}
    }
}
/// Lifecycle and UI state are main-thread confined; SCStream's non-main delegate only dispatches to main.
final class RecordingController:NSObject,SCStreamDelegate,@unchecked Sendable {
    private(set) var state:RecordingState = .idle {didSet{onStateChanged?(state)}}
    var onStateChanged:((RecordingState)->Void)?
    var onFinished:((URL?,String?)->Void)?
    private var output:RecordingOutput?
    private var stream:SCStream?
    private var encoder:RecordingEncoder?
    private var destination:URL?
    private var temporary:URL?
    private var hasBothAudio=false
    private var finishTask:Task<Void,Never>?
    private var activeStarted=0.0,accumulated=0.0
    private var sourceID:CGWindowID?
    private var poll:Timer?
    private var audioListener:AudioObjectPropertyListenerBlock?
    private var systemAudio=false
    var elapsed:Double {accumulated+(state == .recording ? now()-activeStarted:0)}
    var active:Bool{state != .idle}
    @MainActor func start(filter:SCContentFilter,windowID:CGWindowID?,width:Int,height:Int,url:URL,systemAudio:Bool,microphone:Bool,region:RecordingRegion?=nil) async throws {
        guard state == .idle else{throw CaptureFailure.message("已有录屏任务。")}
        if let region=region {
            guard windowID==nil else{throw CaptureFailure.message("区域录屏必须使用显示器来源。")}
            try region.validateCurrentDisplay(pointPixelScale:CGFloat(filter.pointPixelScale))
        }
        state = .preparing;destination=url;sourceID=windowID;self.systemAudio=systemAudio
        let temp=url.deletingLastPathComponent().appendingPathComponent(".snapliq-record-"+UUID().uuidString+".mp4")
        temporary=temp;hasBothAudio=systemAudio && microphone
        do {
            if microphone {
                guard #available(macOS 15.0,*) else{throw CaptureFailure.message("此版本的麦克风录制需要 macOS 15 或更新版本。")}
                guard await AVCaptureDevice.requestAccess(for:.audio) else{throw CaptureFailure.message("麦克风权限未开启。")}
            }
            let config=SCStreamConfiguration();config.width=width/2*2;config.height=height/2*2
            if let region=region {
                try region.validateCurrentDisplay(pointPixelScale:CGFloat(filter.pointPixelScale))
                config.sourceRect=region.sourceRect
                config.width=region.pixelWidth;config.height=region.pixelHeight
                config.destinationRect=CGRect(x:0,y:0,width:config.width,height:config.height)
                config.scalesToFit=false
            }
            config.minimumFrameInterval=CMTime(value:1,timescale:30);config.queueDepth=3
            config.pixelFormat=kCVPixelFormatType_32BGRA;config.showsCursor=true
            config.colorSpaceName=CGColorSpace.sRGB
            config.capturesAudio=systemAudio;config.excludesCurrentProcessAudio=true;config.sampleRate=48000;config.channelCount=2
            if #available(macOS 15.0,*){config.captureMicrophone=microphone}
            let encoder=try RecordingEncoder(url:temp,width:config.width,height:config.height,systemAudio:systemAudio,microphone:microphone)
            self.encoder=encoder
            encoder.errorHandler={ [weak self] error in DispatchQueue.main.async{self?.stop(reason:error.localizedDescription)} }
            let output=RecordingOutput(encoder);self.output=output
            let stream=SCStream(filter:filter,configuration:config,delegate:self);self.stream=stream
            try stream.addStreamOutput(output,type:.screen,sampleHandlerQueue:encoder.queue)
            if systemAudio{try stream.addStreamOutput(output,type:.audio,sampleHandlerQueue:encoder.queue)}
            if #available(macOS 15.0,*),microphone{try stream.addStreamOutput(output,type:.microphone,sampleHandlerQueue:encoder.queue)}
            try await stream.startCapture()
            activeStarted=now();accumulated=0;state = .recording
            NotificationCenter.default.addObserver(self,selector:#selector(interrupted),name:NSApplication.didChangeScreenParametersNotification,object:nil)
            NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(interrupted),name:NSWorkspace.willSleepNotification,object:nil)
            poll=Timer.scheduledTimer(withTimeInterval:1,repeats:true){[weak self] _ in self?.checkSource()}
            if systemAudio || microphone{installAudioListener()}
            Metrics.shared.write("recording_started",["systemAudio":systemAudio,"microphone":microphone,"width":config.width,"height":config.height,"region":region != nil])
        } catch {
            if let stream=stream{try? await stream.stopCapture()}
            encoder?.cancel();self.encoder=nil;self.output=nil;stream=nil
            try? FileManager.default.removeItem(at:temp);temporary=nil;state = .idle;throw error
        }
    }
    func stream(_ stream:SCStream,didStopWithError error:Error){DispatchQueue.main.async{[weak self] in self?.stop(reason:error.localizedDescription)}}
    func togglePause(){
        if state == .recording{accumulated+=now()-activeStarted;encoder?.setPaused(true);state = .paused}
        else if state == .paused{encoder?.setPaused(false);activeStarted=now();state = .recording}
        Metrics.shared.write("recording_state",["state":state.rawValue,"elapsed":elapsed])
    }
    @objc private func interrupted(){stop(reason:"显示器变化或系统即将休眠，录屏已停止并尝试保存。")}
    private func checkSource(){
        if !CGPreflightScreenCaptureAccess(){stop(reason:"屏幕权限已撤销。");return}
        guard let id=sourceID else{return}
        if (CGWindowListCopyWindowInfo([.optionIncludingWindow],id) as? [[String:Any]])?.isEmpty != false {
            stop(reason:"来源窗口已关闭，录屏已停止。")
        }
    }
    private func installAudioListener(){
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultInputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        let listener:AudioObjectPropertyListenerBlock={ [weak self] _,_ in self?.stop(reason:"音频设备发生变化，录屏已停止并尝试保存。") }
        audioListener=listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&address,DispatchQueue.main,listener)
        address.mSelector=kAudioHardwarePropertyDefaultOutputDevice
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&address,DispatchQueue.main,listener)
    }
    private func removeListeners(){
        poll?.invalidate();poll=nil;NotificationCenter.default.removeObserver(self);NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let listener=audioListener {
            for selector in [kAudioHardwarePropertyDefaultInputDevice,kAudioHardwarePropertyDefaultOutputDevice] {
                var address=AudioObjectPropertyAddress(mSelector:selector,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&address,DispatchQueue.main,listener)
            }
        };audioListener=nil
    }
    func stop(reason:String?=nil){
        guard state == .recording || state == .paused else{return}
        if state == .recording{accumulated+=now()-activeStarted}
        state = .finishing;removeListeners()
        let stream=self.stream,encoder=self.encoder,temp=temporary,target=destination,both=hasBothAudio
        finishTask=Task { @MainActor [weak self] in
            guard let self=self else{return}
            if let stream=stream{try? await stream.stopCapture()}
            var final:URL?,failure=reason
            do {
                guard let encoder=encoder,let temp=temp,let target=target else{throw CaptureFailure.message("录屏会话已失效。")}
                try await encoder.finish(duration:self.accumulated)
                let ready:URL
                if both {
                    let mixed=temp.deletingLastPathComponent().appendingPathComponent(".snapliq-mixed-"+UUID().uuidString+".mp4")
                    do{try await RecordingEncoder.mixAudio(from:temp,to:mixed)}catch{try? FileManager.default.removeItem(at:mixed);throw error}
                    try? FileManager.default.removeItem(at:temp);ready=mixed
                } else{ready=temp}
                do {
                    if FileManager.default.fileExists(atPath:target.path){_ = try FileManager.default.replaceItemAt(target,withItemAt:ready)}
                    else{try FileManager.default.moveItem(at:ready,to:target)}
                }catch{throw CaptureFailure.message("录屏已封装，但保存失败。可恢复文件：\(ready.path)\n\(error.localizedDescription)")}
                final=target
                Metrics.shared.write("recording_finished",["seconds":self.accumulated,"frames":encoder.frameCount,"dropped":encoder.dropped])
            }catch {
                failure=error.localizedDescription
                // Keep nonempty finalized/partial files for explicit recovery; never erase user footage on an error.
                Metrics.shared.write("recording_failed",["error":error.localizedDescription,"recovery":temp?.path ?? ""])
            }
            self.stream=nil;self.encoder=nil;self.output=nil;self.temporary=nil;self.destination=nil;self.state = .idle;self.finishTask=nil
            self.onFinished?(final,failure)
        }
    }
}
