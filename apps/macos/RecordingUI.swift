import AppKit
import ScreenCaptureKit
final class RecordingControlPanel:NSPanel {
    override var canBecomeKey:Bool{true}
    override var canBecomeMain:Bool{false}
}
final class RecordingUI:NSWindowController,NSWindowDelegate {
    private let controller:RecordingController
    private let sources=NSPopUpButton()
    private let system=NSButton(checkboxWithTitle:L("录制系统声音","Record system audio"),target:nil,action:nil)
    private let microphone=NSButton(checkboxWithTitle:L("录制麦克风","Record microphone"),target:nil,action:nil)
    private let sourceHeading=NSTextField(labelWithString:"")
    private var regionButton:NSButton?
    private let status=NSTextField(wrappingLabelWithString:"")
    private var statusText:()->String = {L("正在读取屏幕和窗口…","Loading displays and windows…")}
    private var content:SCShareableContent?
    private var choices=[(SCDisplay?,SCWindow?,RecordingRegion?)]()
    var onChooseRegion:(()->Void)?
    private var startButton:NSButton!
    private var generation=0
    private(set) var starting=false {didSet{onStartingChanged?()}}
    var onStartingChanged:(()->Void)?
    private var controlState:RecordingState = .idle
    private var scopedFolder:URL?
    var onPreferencesChanged:(()->Void)?
    private var controls:NSPanel?
    private var timer:Timer?
    private let duration=NSTextField(labelWithString:"")
    private var pauseButton:NSButton!
    private var stopButton:NSButton!
    init(controller:RecordingController){
        self.controller=controller;super.init(window:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshLanguage),name:.snapliqLanguageChanged,object:Localization.shared)
    }
    required init?(coder:NSCoder){fatalError()}
    deinit{timer?.invalidate();NotificationCenter.default.removeObserver(self)}
    private func sourceTitle(_ choice:(SCDisplay?,SCWindow?,RecordingRegion?))->String{
        if let region=choice.2{return L("区域 · \(region.pixelWidth) × \(region.pixelHeight) px · 屏幕 \(region.displayID)","Region · \(region.pixelWidth) × \(region.pixelHeight) px · Display \(region.displayID)")}
        if let display=choice.0{return L("屏幕 \(display.displayID) · \(display.width) × \(display.height)","Display \(display.displayID) · \(display.width) × \(display.height)")}
        if let window=choice.1{return "\(window.owningApplication?.applicationName ?? L("应用","Application")) — \(window.title ?? L("窗口","Window"))"}
        return L("来源不可用","Source unavailable")
    }
    private func setStatus(_ text:@escaping()->String){statusText=text;status.stringValue=text()}
    @objc private func refreshLanguage(){
        window?.title=L("屏幕录制 · \(Product.name)","Screen recording · \(Product.name)")
        sourceHeading.stringValue=L("选择屏幕、窗口或区域","Choose a display, window or region")
        regionButton?.title=L("框选录制区域…","Select recording region…")
        system.title=L("录制系统声音","Record system audio")
        if #available(macOS 15.0,*){microphone.title=L("录制麦克风","Record microphone")}
        else{microphone.title=L("麦克风录制需要 macOS 15+","Microphone recording requires macOS 15+")}
        startButton?.title=L("开始录制","Start recording")
        // Retain the live source list, selected index and audio choices while relabeling it.
        for (index,choice) in choices.enumerated(){sources.item(at:index)?.title=sourceTitle(choice)}
        status.stringValue=statusText()
        refreshControlText()
    }
    private func refreshControlText(){
        controls?.title=L("Snapliq 录屏控制","Snapliq recording controls")
        pauseButton?.title=controlState == .paused ? L("继续","Resume"):L("暂停","Pause")
        pauseButton?.setAccessibilityLabel(controlState == .paused ? L("继续录屏","Resume recording"):L("暂停录屏","Pause recording"))
        pauseButton?.setAccessibilityHelp(L("暂停录制；暂停期间不会计入视频时长。","Pause recording. Paused time is excluded from the video duration."))
        stopButton?.title=L("停止","Stop")
        stopButton?.setAccessibilityLabel(L("停止并保存录屏","Stop and save recording"))
        stopButton?.setAccessibilityHelp(L("结束录制并完成视频文件保存。","Stop recording and finish saving the video."))
        updateDuration()
    }
    func present(region:RecordingRegion?=nil,errorMessage:String?=nil){
        guard !starting,!controller.active else{controls?.makeKeyAndOrderFront(nil);controls?.selectNextKeyView(nil);return}
        if window==nil {
            let w=NSWindow(contentRect:.init(x:0,y:0,width:560,height:420),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            w.title=L("屏幕录制 · \(Product.name)","Screen recording · \(Product.name)");w.isReleasedWhenClosed=false;w.delegate=self;window=w
            let root=NSStackView();root.orientation = .vertical;root.alignment = .leading;root.spacing=18
            root.translatesAutoresizingMaskIntoConstraints=false;w.contentView!.addSubview(root)
            NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:w.contentView!.leadingAnchor,constant:24),root.trailingAnchor.constraint(equalTo:w.contentView!.trailingAnchor,constant:-24),root.topAnchor.constraint(equalTo:w.contentView!.topAnchor,constant:24)])
            sourceHeading.font = .systemFont(ofSize:18,weight:.semibold)
            root.addArrangedSubview(sourceHeading);root.addArrangedSubview(sources);sources.widthAnchor.constraint(equalToConstant:500).isActive=true
            sources.setAccessibilityIdentifier("snapliq.recording.sources")
            let choose=NSButton(title:L("框选录制区域…","Select recording region…"),target:self,action:#selector(chooseRegion));choose.bezelStyle = .rounded;regionButton=choose
            choose.setAccessibilityIdentifier("snapliq.recording.chooseRegion")
            root.addArrangedSubview(choose)
            root.addArrangedSubview(system);root.addArrangedSubview(microphone)
            system.target=self;system.action=#selector(audioChanged)
            microphone.target=self;microphone.action=#selector(audioChanged)
            system.setAccessibilityIdentifier("snapliq.recording.systemAudio")
            microphone.setAccessibilityIdentifier("snapliq.recording.microphone")
            if #available(macOS 15.0,*){}else{microphone.isEnabled=false;microphone.title=L("麦克风录制需要 macOS 15+","Microphone recording requires macOS 15+")}
            startButton=NSButton(title:L("开始录制","Start recording"),target:self,action:#selector(start));startButton.bezelStyle = .rounded
            root.addArrangedSubview(startButton);status.font = .systemFont(ofSize:12);status.textColor = .secondaryLabelColor;status.preferredMaxLayoutWidth=500;root.addArrangedSubview(status)
        }
        refreshPreferences();refreshLanguage()
        setStatus{L("正在读取屏幕和窗口…","Loading displays and windows…")}
        window?.center();showWindow(nil);NSApp.activate(ignoringOtherApps:true)
        generation+=1;let token=generation;startButton.isEnabled=false;sources.removeAllItems();choices=[]
        Task { @MainActor [weak self] in
            guard let self=self else{return}
            do {
                let content=try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
                guard self.generation==token else{return};self.content=content
                if let region=region {
                    guard let display=content.displays.first(where:{$0.displayID==region.displayID}) else{throw CaptureFailure.message(L("显示器已断开，请重新框选。","The display disconnected. Select the region again."))}
                    let filter=SCContentFilter(display:display,excludingApplications:[],exceptingWindows:[])
                    try region.validateCurrentDisplay(pointPixelScale:CGFloat(filter.pointPixelScale))
                    self.choices.append((display,nil,region))
                    self.sources.addItem(withTitle:self.sourceTitle((display,nil,region)))
                }
                for d in content.displays {self.choices.append((d,nil,nil));self.sources.addItem(withTitle:self.sourceTitle((d,nil,nil)))}
                for w in content.windows where w.owningApplication?.processID != getpid() && w.windowLayer==0 && w.frame.width>40 && w.frame.height>40 {
                    self.choices.append((nil,w,nil));self.sources.addItem(withTitle:self.sourceTitle((nil,w,nil)))
                }
                self.startButton.isEnabled = !self.choices.isEmpty
                self.setStatus{errorMessage ?? L("30 fps · MP4 · 自动保存到默认文件夹。\n快捷键 \(Preferences.shared.recordingShortcutLabel) 直接录制鼠标所在屏幕，再按结束。","30 fps · MP4 · Saves automatically to the default folder.\nPress \(Preferences.shared.recordingShortcutLabel) to record the display under the pointer; press again to stop.")}
            } catch {self.setStatus{L("无法读取来源：\(error.localizedDescription)","Could not load sources: \(error.localizedDescription)")}}
        }
    }
    @objc private func chooseRegion(){
        guard !controller.active else{return}
        generation+=1;window?.orderOut(nil);onChooseRegion?()
    }
    func refreshPreferences(){
        system.state=Preferences.shared.recordSystemAudio ? .on:.off
        if #available(macOS 15.0,*){microphone.state=Preferences.shared.recordMicrophone ? .on:.off}
        else{microphone.state = .off}
    }
    @objc private func audioChanged(){
        Preferences.shared.recordSystemAudio=system.state == .on
        if #available(macOS 15.0,*){Preferences.shared.recordMicrophone=microphone.state == .on}
        onPreferencesChanged?()
    }
    /// Latch before source discovery: repeated hotkeys cannot launch competing streams.
    func quickToggle(){
        guard !starting else{return}
        switch controller.state {
        case .recording,.paused:controller.stop();return
        case .preparing,.finishing:return
        case .idle:break
        }
        let point=NSEvent.mouseLocation
        let screen=NSScreen.screens.first(where:{$0.frame.contains(point)}) ?? NSScreen.main
        guard let displayID=(screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            showError(L("找不到可录制的屏幕。","No display is available for recording."));return
        }
        generation+=1;starting=true;window?.orderOut(nil);refreshPreferences()
        // Own controls must exist before enumerating applications, so the exclusion filter includes us.
        update(.preparing)
        Metrics.shared.write("quick_record_trigger",["displayID":displayID])
        Task { @MainActor [weak self] in
            guard let self=self else{return}
            defer{self.starting=false}
            do {
                let content=try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
                guard let display=content.displays.first(where:{$0.displayID==displayID}) else {
                    throw CaptureFailure.message(L("显示器已断开，请重新开始录屏。","The display disconnected. Start a new recording."))
                }
                try await self.beginRecording(content:content,display:display,window:nil,region:nil)
            } catch {self.update(.idle);showError(L("无法开始录屏：\(error.localizedDescription)","Could not start recording: \(error.localizedDescription)"))}
        }
    }
    @objc private func start(){
        guard !starting,!controller.active,let content=content,sources.indexOfSelectedItem>=0,sources.indexOfSelectedItem<choices.count else{return}
        let (display,window,region)=choices[sources.indexOfSelectedItem]
        generation+=1;starting=true;self.window?.orderOut(nil);startButton.isEnabled=false;update(.preparing)
        Task { @MainActor [weak self] in
            guard let self=self else{return}
            do {
                try await self.beginRecording(content:content,display:display,window:window,region:region)
                self.starting=false
            } catch {
                self.starting=false;self.update(.idle);self.present(errorMessage:error.localizedDescription)
            }
        }
    }
    @MainActor private func beginRecording(content:SCShareableContent,display:SCDisplay?,window:SCWindow?,region:RecordingRegion?) async throws {
        let filter:SCContentFilter
        if let display=display {
            filter=SCContentFilter(display:display,excludingApplications:content.applications.filter{$0.processID==getpid()},exceptingWindows:[])
            if #available(macOS 14.2,*){filter.includeMenuBar=true}
        } else if let window=window {filter=SCContentFilter(desktopIndependentWindow:window)}
        else{throw CaptureFailure.message(L("找不到可录制的来源。","No source is available for recording."))}
        let url=try RecordingDestination.makeURL()
        let folder=url.deletingLastPathComponent()
        if folder.startAccessingSecurityScopedResource(){scopedFolder=folder}
        let scale=CGFloat(filter.pointPixelScale)
        let width=region?.pixelWidth ?? Int(filter.contentRect.width*scale),height=region?.pixelHeight ?? Int(filter.contentRect.height*scale)
        let mic:Bool
        if #available(macOS 15.0,*){mic=Preferences.shared.recordMicrophone}else{mic=false}
        try await controller.start(filter:filter,windowID:window?.windowID,width:width,height:height,url:url,
                                   systemAudio:Preferences.shared.recordSystemAudio,microphone:mic,region:region,overwriteExisting:false)
        Metrics.shared.write("quick_record_ready",["source":region != nil ? "region":(window != nil ? "window":"screen")])
    }
    func update(_ state:RecordingState){
        controlState=state
        if state == .idle {timer?.invalidate();timer=nil;controls?.close();controls=nil;scopedFolder?.stopAccessingSecurityScopedResource();scopedFolder=nil;return}
        if controls==nil {
            let p=RecordingControlPanel(contentRect:.init(x:0,y:0,width:380,height:52),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.isReleasedWhenClosed=false;p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=true;p.hidesOnDeactivate=false
            p.title=L("Snapliq 录屏控制","Snapliq recording controls");p.setAccessibilityIdentifier("snapliq.recording.controls")
            p.isFloatingPanel=true;p.becomesKeyOnlyIfNeeded=true
            p.level = .statusBar;p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
            let root=materialView(radius:16);root.frame = .init(x:0,y:0,width:380,height:52);p.contentView=root
            duration.font = .monospacedDigitSystemFont(ofSize:13,weight:.semibold)
            pauseButton=NSButton(title:L("暂停","Pause"),target:self,action:#selector(pause));pauseButton.bezelStyle = .rounded
            pauseButton.setAccessibilityIdentifier("snapliq.recording.pause")
            stopButton=NSButton(title:L("停止","Stop"),target:self,action:#selector(stop));stopButton.bezelStyle = .rounded
            stopButton.setAccessibilityIdentifier("snapliq.recording.stop")
            pauseButton.nextKeyView=stopButton;stopButton.nextKeyView=pauseButton;p.initialFirstResponder=pauseButton
            duration.setAccessibilityIdentifier("snapliq.recording.duration")
            let stack=NSStackView(views:[duration,pauseButton,stopButton]);stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(stack)
            NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo:root.centerXAnchor),stack.centerYAnchor.constraint(equalTo:root.centerYAnchor)])
            if let screen=NSScreen.main{p.setFrameOrigin(.init(x:screen.visibleFrame.midX-190,y:screen.visibleFrame.maxY-75))}
            controls=p;p.orderFrontRegardless()
            timer=Timer.scheduledTimer(withTimeInterval:0.5,repeats:true){[weak self] _ in self?.updateDuration()}
        }
        refreshControlText()
        pauseButton.isEnabled=state == .recording || state == .paused
        stopButton.isEnabled=state == .recording || state == .paused
        updateDuration()
    }
    private func updateDuration(){
        let seconds=controlState == .preparing ? 0:Int(controller.elapsed)
        let label:String
        switch controlState {
        case .preparing:label=L("正在准备","Preparing")
        case .paused:label=L("Ⅱ 已暂停","Ⅱ Paused")
        case .finishing:label=L("正在保存","Saving")
        case .recording:label=L("● 录制中","● Recording")
        case .idle:label=L("已停止","Stopped")
        }
        duration.stringValue=String(format:"%@ %02d:%02d",label,seconds/60,seconds%60)
    }
    @objc private func pause(){controller.togglePause()}
    @objc private func stop(){controller.stop()}
    func windowWillClose(_ notification:Notification){generation+=1}
}
