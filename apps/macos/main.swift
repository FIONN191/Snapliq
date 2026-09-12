import AppKit
import ScreenCaptureKit
final class AppDelegate:NSObject,NSApplicationDelegate {
    let bridge=DesktopBridge()
    let backend=CaptureBackend()
    let hotkey=HotkeyService()
    let orb=OrbController()
    let settings=SettingsController()
    let recorder=RecordingController()
    lazy var recordingUI:RecordingUI = {
        let ui=RecordingUI(controller:recorder)
        ui.onChooseRegion={ [weak self] in self?.begin(.region,trigger:"recording_region",recordingSelection:true) }
        return ui
    }()
    private var waitingToQuit=false
    private var permissionPrompt=false
    private var lastPermissionPrompt=0.0
    private var statusItem:NSStatusItem!
    private var session:SelectionSession?
    private var busy=false
    private var previousApp:NSRunningApplication?
    func applicationDidFinishLaunching(_ notification:Notification){
        let other=NSRunningApplication.runningApplications(withBundleIdentifier:Bundle.main.bundleIdentifier ?? "").filter{$0.processIdentifier != getpid()}
        if !other.isEmpty{other.first?.activate(options:[]);NSApp.terminate(nil);return}
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength);statusItem.button?.image=brandImage()
        statusItem.button?.toolTip="\(Product.name) — 截图开发版";rebuildMenu()
        hotkey.onTrigger={ [weak self] in self?.begin(.region,trigger:"global_hotkey") }
        orb.onCapture={ [weak self] in self?.begin(.region,trigger:"orb") }
        orb.onSettings={ [weak self] in self?.settings.present() }
        orb.onStateChanged={ [weak self] in self?.rebuildMenu();self?.settings.refresh() }
        settings.onCapture={ [weak self] in self?.begin(.region,trigger:"settings") }
        settings.onHotkeyChanged={ [weak self] in self?.hotkey.register() ?? -1 }
        settings.onSuspendHotkey={ [weak self] in self?.hotkey.unregister() }
        settings.onOrbChanged={ [weak self] in self?.orb.refresh();self?.rebuildMenu() }
        bridge.onAction={ [weak self] action in
            guard let self=self else{return}
            switch action {
            case "capture":self.begin(.region,trigger:"chrome_request")
            case "record":self.recordScreen()
            case "settings":self.settings.present()
            default:break
            }
        }
        bridge.start()
        AirDropTransfer.removeStaleFiles()
        recorder.onStateChanged={ [weak self] state in
            guard let self=self else{return}
            self.statusItem.button?.toolTip="Snapliq: "+state.rawValue
            self.recordingUI.update(state);self.orb.view.recordingState=state.rawValue;self.orb.view.needsDisplay=true
            self.rebuildMenu()
        }
        recorder.onFinished={ [weak self] url,error in
            guard let self=self else{return}
            if self.waitingToQuit{NSApp.reply(toApplicationShouldTerminate:true);return}
            if let error=error{showError(error)}
            else if let url=url{self.statusItem.button?.toolTip="已保存录屏："+url.lastPathComponent}
        }
        let result=hotkey.register()
        if result != 0{Preferences.shared.shortcutEnabled=false}
        orb.refresh()
        Metrics.shared.write("launch",["version":Product.version,"pid":getpid(),"screenPermission":CGPreflightScreenCaptureAccess(),"screens":NSScreen.screens.count])
        if CommandLine.arguments.contains("--self-test"){Task{await runDiagnostics(app:self)}}
        else if CommandLine.arguments.contains("--capture"){begin(.region,trigger:"launch_argument")}
        else if !Preferences.shared.defaults.bool(forKey:"onboarded") || CommandLine.arguments.contains("--settings"){
            Preferences.shared.defaults.set(true,forKey:"onboarded");settings.present()
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{false}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if recorder.state == .preparing {showError("录屏正在准备，请稍后退出。");return .terminateCancel}
        if recorder.active {waitingToQuit=true;recorder.stop();return .terminateLater}
        return .terminateNow
    }
    func applicationWillTerminate(_ notification:Notification){bridge.stop();hotkey.unregister();Metrics.shared.write("quit")}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{settings.present();return true}
    private func item(_ title:String,_ action:Selector)->NSMenuItem{let m=NSMenuItem(title:title,action:action,keyEquivalent:"");m.target=self;return m}
    func rebuildMenu(){
        guard statusItem != nil else{return}
        let m=NSMenu();m.addItem(item("区域截图",#selector(region)));m.addItem(item("窗口截图",#selector(windowCapture)));m.addItem(item("当前屏幕截图",#selector(screenCapture)))
        m.addItem(.separator())
        m.addItem(item(recorder.active ? "显示录屏控制条":"屏幕录制…",#selector(recordScreen)))
        if recorder.state == .recording || recorder.state == .paused {
            m.addItem(item(recorder.state == .paused ? "继续录屏":"暂停录屏",#selector(pauseRecording)))
            m.addItem(item("停止并保存录屏",#selector(stopRecording)))
        }
        m.addItem(.separator());m.addItem(item("显示悬浮球",#selector(restoreOrb)));m.addItem(item("设置…",#selector(openSettings)))
        m.addItem(.separator());m.addItem(item("退出 Snapliq",#selector(quit)));statusItem.menu=m
    }
    static func windowCandidates()->[DesktopWindowTarget]{
        guard let list=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] else{return []}
        let top=NSScreen.screens.first?.frame.maxY ?? 0
        return list.compactMap{w in
            guard (w[kCGWindowOwnerPID as String] as? Int) != Int(getpid()),(w[kCGWindowLayer as String] as? Int)==0,
            (w[kCGWindowAlpha as String] as? Double ?? 1)>0,
            let b=w[kCGWindowBounds as String] as? NSDictionary,let r=CGRect(dictionaryRepresentation:b) else{return nil}
            guard r.width>20,r.height>20 else{return nil}
            return DesktopWindowTarget(frame:CGRect(x:r.minX,y:top-r.maxY,width:r.width,height:r.height),pid:pid_t(w[kCGWindowOwnerPID as String] as? Int ?? 0))
        }
    }
    func begin(_ mode:SelectionMode,trigger:String,recordingSelection:Bool=false){
        if recordingSelection && recorder.active{return}
        guard !busy,session==nil else{return}
        guard ensureCapturePermission() else{return}
        busy=true
        let start=now();previousApp=NSWorkspace.shared.frontmostApplication
        let candidates=(mode == .window || Preferences.shared.defaults.bool(forKey:"smartSelection")) ? Self.windowCandidates():[]
        settings.window?.orderOut(nil);orb.temporarilyHidden=true;orb.refresh()
        statusItem.button?.title="…";statusItem.button?.displayIfNeeded()
        Metrics.shared.write("trigger",["source":trigger])
        Metrics.shared.write("feedback_submitted",["ms":(now()-start)*1000,"measurement":"view_submission_not_physical_presentation"])
        Task { @MainActor in
            do {
                let images=try await backend.capture()
                Metrics.shared.write("background_ready",["ms":(now()-start)*1000,"displays":images.map{["id":$0.id,"width":$0.image.width,"height":$0.image.height]}])
                let next=SelectionSession(snapshots:images,started:start,mode:mode,candidates:candidates,recordingSelection:recordingSelection)
                next.onRecord={ [weak self] region in self?.recordingUI.present(region:region) }
                next.onChooseFolder={ [weak self] in self?.settings.chooseFolder() }
                next.onFinish={ [weak self] message in
                    guard let self=self else{return}
                    self.session=nil;self.busy=false;self.orb.temporarilyHidden=false;self.orb.refresh();self.statusItem.button?.title=""
                    if let previous=self.previousApp,previous.processIdentifier != getpid(){previous.activate(options:[])}
                    if let message=message{self.statusItem.button?.toolTip=message;Metrics.shared.write("session_finished",["result":message])}
                }
                session=next;busy=false;statusItem.button?.title="";next.present()
            } catch {
                busy=false;orb.temporarilyHidden=false;orb.refresh();statusItem.button?.title=""
                Metrics.shared.write("capture_failed",["error":error.localizedDescription])
                showError("无法取得桌面底图：\(error.localizedDescription)\n若刚开启屏幕录制权限，请退出并重新打开 Snapliq。")
            }
        }
    }
    func ensureCapturePermission()->Bool {
        if CGPreflightScreenCaptureAccess(){return true}
        Metrics.shared.write("permission_required")
        guard !permissionPrompt,now()-lastPermissionPrompt>2 else{return false}
        permissionPrompt=true;lastPermissionPrompt=now();defer{permissionPrompt=false}
        if CGRequestScreenCaptureAccess(){return true}
        NSApp.activate(ignoringOtherApps:true)
        let alert=NSAlert();alert.messageText="当前版本尚未获得屏幕捕获权限"
        alert.informativeText="请在系统设置中允许 Snapliq，然后退出并重新打开。若权限开关已开启，开发版更新可能改变了签名，需要移除旧 Snapliq 条目并重新添加当前应用。快捷键已经收到，截图尚未开始。"
        alert.addButton(withTitle:"打开系统权限设置");alert.addButton(withTitle:"稍后")
        if alert.runModal() == .alertFirstButtonReturn{NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)}
        return false
    }
    @objc func recordScreen(){
        guard ensureCapturePermission() else{return}
        settings.window?.orderOut(nil);recordingUI.present()
    }
    @objc func pauseRecording(){recorder.togglePause()}
    @objc func stopRecording(){recorder.stop()}
    @objc func region(){begin(.region,trigger:"menu")}
    @objc func windowCapture(){begin(.window,trigger:"menu")}
    @objc func screenCapture(){begin(.screen,trigger:"menu")}
    @objc func restoreOrb(){orb.restore();rebuildMenu()}
    @objc func openSettings(){settings.present()}
    @objc func quit(){NSApp.terminate(nil)}
}
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate=AppDelegate()
app.delegate=delegate
app.run()
