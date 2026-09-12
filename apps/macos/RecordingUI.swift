import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers
final class RecordingControlPanel:NSPanel {
    override var canBecomeKey:Bool{true}
    override var canBecomeMain:Bool{false}
}
final class RecordingUI:NSWindowController,NSWindowDelegate {
    private let controller:RecordingController
    private let sources=NSPopUpButton()
    private let system=NSButton(checkboxWithTitle:"录制系统声音",target:nil,action:nil)
    private let microphone=NSButton(checkboxWithTitle:"录制麦克风",target:nil,action:nil)
    private let status=NSTextField(wrappingLabelWithString:"正在读取屏幕和窗口…")
    private var content:SCShareableContent?
    private var choices=[(SCDisplay?,SCWindow?,RecordingRegion?)]()
    var onChooseRegion:(()->Void)?
    private var startButton:NSButton!
    private var generation=0
    private var controls:NSPanel?
    private var timer:Timer?
    private let duration=NSTextField(labelWithString:"")
    private var pauseButton:NSButton!
    private var stopButton:NSButton!
    init(controller:RecordingController){self.controller=controller;super.init(window:nil)}
    required init?(coder:NSCoder){fatalError()}
    func present(region:RecordingRegion?=nil){
        guard !controller.active else{controls?.makeKeyAndOrderFront(nil);controls?.selectNextKeyView(nil);return}
        if window==nil {
            let w=NSWindow(contentRect:.init(x:0,y:0,width:530,height:400),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            w.title="屏幕录制 · \(Product.name)";w.isReleasedWhenClosed=false;w.delegate=self;window=w
            let root=NSStackView();root.orientation = .vertical;root.alignment = .leading;root.spacing=18
            root.translatesAutoresizingMaskIntoConstraints=false;w.contentView!.addSubview(root)
            NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:w.contentView!.leadingAnchor,constant:24),root.trailingAnchor.constraint(equalTo:w.contentView!.trailingAnchor,constant:-24),root.topAnchor.constraint(equalTo:w.contentView!.topAnchor,constant:24)])
            let label=NSTextField(labelWithString:"选择屏幕、窗口或区域");label.font = .systemFont(ofSize:18,weight:.semibold)
            root.addArrangedSubview(label);root.addArrangedSubview(sources);sources.widthAnchor.constraint(equalToConstant:470).isActive=true
            let choose=NSButton(title:"框选录制区域…",target:self,action:#selector(chooseRegion));choose.bezelStyle = .rounded
            choose.setAccessibilityIdentifier("snapliq.recording.chooseRegion")
            root.addArrangedSubview(choose)
            root.addArrangedSubview(system);root.addArrangedSubview(microphone)
            if #available(macOS 15.0,*){}else{microphone.isEnabled=false;microphone.title="麦克风录制需要 macOS 15+"}
            startButton=NSButton(title:"选择保存文件并开始…",target:self,action:#selector(start));startButton.bezelStyle = .rounded
            root.addArrangedSubview(startButton);status.font = .systemFont(ofSize:12);status.textColor = .secondaryLabelColor;status.preferredMaxLayoutWidth=470;root.addArrangedSubview(status)
        }
        window?.center();showWindow(nil);NSApp.activate(ignoringOtherApps:true)
        generation+=1;let token=generation;startButton.isEnabled=false;sources.removeAllItems();choices=[]
        Task { @MainActor [weak self] in
            guard let self=self else{return}
            do {
                let content=try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
                guard self.generation==token else{return};self.content=content
                if let region=region {
                    guard let display=content.displays.first(where:{$0.displayID==region.displayID}) else{throw CaptureFailure.message("显示器已断开，请重新框选。")}
                    let filter=SCContentFilter(display:display,excludingApplications:[],exceptingWindows:[])
                    try region.validateCurrentDisplay(pointPixelScale:CGFloat(filter.pointPixelScale))
                    self.choices.append((display,nil,region))
                    self.sources.addItem(withTitle:"区域 · \(region.pixelWidth) × \(region.pixelHeight) px · 屏幕 \(region.displayID)")
                }
                for d in content.displays {self.choices.append((d,nil,nil));self.sources.addItem(withTitle:"屏幕 \(d.displayID) · \(d.width) × \(d.height)")}
                for w in content.windows where w.owningApplication?.processID != getpid() && w.windowLayer==0 && w.frame.width>40 && w.frame.height>40 {
                    self.choices.append((nil,w,nil));self.sources.addItem(withTitle:"\(w.owningApplication?.applicationName ?? "应用") — \(w.title ?? "窗口")")
                }
                self.startButton.isEnabled = !self.choices.isEmpty
                self.status.stringValue="30 fps · MP4 · 暂停会移除暂停时段。\n区域录屏限单个显示器；输出尺寸向内对齐偶数像素。"
            } catch {self.status.stringValue="无法读取来源：\(error.localizedDescription)"}
        }
    }
    @objc private func chooseRegion(){
        guard !controller.active else{return}
        generation+=1;window?.orderOut(nil);onChooseRegion?()
    }
    @objc private func start(){
        guard let content=content,sources.indexOfSelectedItem>=0,sources.indexOfSelectedItem<choices.count else{return}
        let (display,window,region)=choices[sources.indexOfSelectedItem]
        let filter:SCContentFilter
        if let display=display {
            filter=SCContentFilter(display:display,excludingApplications:content.applications.filter{$0.processID==getpid()},exceptingWindows:[])
            if #available(macOS 14.2,*){filter.includeMenuBar=true}
        } else if let window=window {filter=SCContentFilter(desktopIndependentWindow:window)}
        else{return}
        let panel=NSSavePanel();panel.allowedContentTypes=[.mpeg4Movie];panel.nameFieldStringValue=Product.name+"-"+Self.timestamp()+".mp4";panel.directoryURL=Preferences.shared.folderURL
        guard panel.runModal() == .OK,let url=panel.url else{return}
        let scale=CGFloat(filter.pointPixelScale)
        let width=region?.pixelWidth ?? Int(filter.contentRect.width*scale),height=region?.pixelHeight ?? Int(filter.contentRect.height*scale)
        self.window?.orderOut(nil)
        startButton.isEnabled=false
        Task { @MainActor [weak self] in
            guard let self=self else{return}
            do{try await self.controller.start(filter:filter,windowID:window?.windowID,width:width,height:height,url:url,systemAudio:self.system.state == .on,microphone:self.microphone.state == .on,region:region)}
            catch{self.present();self.status.stringValue=error.localizedDescription}
        }
    }
    private static func timestamp()->String{let f=DateFormatter();f.dateFormat="yyyy-MM-dd_HH-mm-ss";return f.string(from:Date())}
    func update(_ state:RecordingState){
        if state == .idle {timer?.invalidate();timer=nil;controls?.close();controls=nil;return}
        if state == .preparing{return}
        if controls==nil {
            let p=RecordingControlPanel(contentRect:.init(x:0,y:0,width:340,height:52),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.isReleasedWhenClosed=false;p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=true;p.hidesOnDeactivate=false
            p.title="Snapliq 录屏控制";p.setAccessibilityIdentifier("snapliq.recording.controls")
            p.isFloatingPanel=true;p.becomesKeyOnlyIfNeeded=true
            p.level = .statusBar;p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
            let root=materialView(radius:16);root.frame = .init(x:0,y:0,width:340,height:52);p.contentView=root
            duration.font = .monospacedDigitSystemFont(ofSize:13,weight:.semibold)
            pauseButton=NSButton(title:"暂停",target:self,action:#selector(pause));pauseButton.bezelStyle = .rounded
            pauseButton.setAccessibilityIdentifier("snapliq.recording.pause")
            pauseButton.setAccessibilityHelp("暂停录制；暂停期间不会计入视频时长。")
            stopButton=NSButton(title:"停止",target:self,action:#selector(stop));stopButton.bezelStyle = .rounded
            stopButton.setAccessibilityIdentifier("snapliq.recording.stop");stopButton.setAccessibilityLabel("停止并保存录屏")
            stopButton.setAccessibilityHelp("结束录制并完成视频文件保存。")
            pauseButton.nextKeyView=stopButton;stopButton.nextKeyView=pauseButton;p.initialFirstResponder=pauseButton
            duration.setAccessibilityIdentifier("snapliq.recording.duration")
            let stack=NSStackView(views:[duration,pauseButton,stopButton]);stack.spacing=14;stack.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(stack)
            NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo:root.centerXAnchor),stack.centerYAnchor.constraint(equalTo:root.centerYAnchor)])
            if let screen=NSScreen.main{p.setFrameOrigin(.init(x:screen.visibleFrame.midX-170,y:screen.visibleFrame.maxY-75))}
            controls=p;p.orderFrontRegardless()
            timer=Timer.scheduledTimer(withTimeInterval:0.5,repeats:true){[weak self] _ in self?.updateDuration()}
        }
        pauseButton.title=state == .paused ? "继续":"暂停"
        pauseButton.setAccessibilityLabel(state == .paused ? "继续录屏":"暂停录屏")
        pauseButton.isEnabled=state == .recording || state == .paused
        stopButton.isEnabled=state == .recording || state == .paused
        updateDuration()
    }
    private func updateDuration(){
        let seconds=Int(controller.elapsed)
        let label=controller.state == .paused ? "Ⅱ 已暂停":(controller.state == .finishing ? "正在封装":"● 录制中")
        duration.stringValue=String(format:"%@ %02d:%02d",label,seconds/60,seconds%60)
    }
    @objc private func pause(){controller.togglePause()}
    @objc private func stop(){controller.stop()}
    func windowWillClose(_ notification:Notification){generation+=1}
}
