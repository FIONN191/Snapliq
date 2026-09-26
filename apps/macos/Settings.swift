import AppKit
import Carbon
import ServiceManagement
final class ShortcutRecorder:NSButton {
    var recording=false
    var onRecord:((NSEvent)->Void)?
    override var acceptsFirstResponder:Bool{true}
    override func keyDown(with event:NSEvent){if recording{onRecord?(event)}else{super.keyDown(with:event)}}
    override func performKeyEquivalent(with event:NSEvent)->Bool{if recording{onRecord?(event);return true};return super.performKeyEquivalent(with:event)}
}
private final class SettingsDocumentView:NSView {override var isFlipped:Bool{true}}
final class SettingsController:NSWindowController,NSWindowDelegate {
    var onCapture:(()->Void)?
    var onQuickRecord:(()->Void)?
    var onOrbChanged:(()->Void)?
    var onHotkeyChanged:(()->OSStatus)?
    var onRecordingHotkeyChanged:(()->OSStatus)?
    // The app suspends both registrations while either shortcut is being edited.
    var onSuspendHotkey:(()->Void)?
    var onRecordingPreferencesChanged:(()->Void)?
    private let shortcut=ShortcutRecorder(title:"",target:nil,action:nil)
    private let recordingShortcut=ShortcutRecorder(title:"",target:nil,action:nil)
    private let hotkeyToggle=NSButton(checkboxWithTitle:"启用全局截图快捷键",target:nil,action:nil)
    private let recordingHotkeyToggle=NSButton(checkboxWithTitle:"启用全局录屏快捷键",target:nil,action:nil)
    private let systemAudioToggle=NSButton(checkboxWithTitle:"录制系统声音",target:nil,action:nil)
    private let microphoneToggle=NSButton(checkboxWithTitle:"录制麦克风",target:nil,action:nil)
    private let orbToggle=NSButton(checkboxWithTitle:"显示桌面悬浮球",target:nil,action:nil)
    private let loginToggle=NSButton(checkboxWithTitle:"登录时启动 Snapliq",target:nil,action:nil)
    private let folder=NSTextField(labelWithString:"")
    private let permission=NSTextField(labelWithString:"")
    private let status=NSTextField(wrappingLabelWithString:"")
    init(){
        let contentHeight=min(710,max(400,(NSScreen.main?.visibleFrame.height ?? 800)-80))
        let w=NSWindow(contentRect:.init(x:0,y:0,width:550,height:contentHeight),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        w.title="\(Product.name) 设置";w.isReleasedWhenClosed=false;w.minSize=NSSize(width:520,height:450)
        super.init(window:w);w.delegate=self
        let scroll=NSScrollView();scroll.translatesAutoresizingMaskIntoConstraints=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.drawsBackground=false
        w.contentView!.addSubview(scroll)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo:w.contentView!.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:w.contentView!.trailingAnchor),scroll.topAnchor.constraint(equalTo:w.contentView!.topAnchor),scroll.bottomAnchor.constraint(equalTo:w.contentView!.bottomAnchor)])
        let document=SettingsDocumentView();document.translatesAutoresizingMaskIntoConstraints=false;scroll.documentView=document
        let root=NSStackView();root.orientation = .vertical;root.alignment = .leading;root.spacing=14
        root.translatesAutoresizingMaskIntoConstraints=false;document.addSubview(root)
        NSLayoutConstraint.activate([document.leadingAnchor.constraint(equalTo:scroll.contentView.leadingAnchor),document.topAnchor.constraint(equalTo:scroll.contentView.topAnchor),document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),root.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:30),root.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-30),root.topAnchor.constraint(equalTo:document.topAnchor,constant:25),root.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-25)])
        let title=NSTextField(labelWithString:Product.name);title.font = .systemFont(ofSize:28,weight:.semibold)
        let subtitle=NSTextField(labelWithString:Product.tagline);subtitle.textColor = .secondaryLabelColor
        root.addArrangedSubview(title);root.addArrangedSubview(subtitle)
        hotkeyToggle.target=self;hotkeyToggle.action=#selector(toggleShortcut);root.addArrangedSubview(hotkeyToggle)
        shortcut.target=self;shortcut.action=#selector(recordShortcut);shortcut.bezelStyle = .rounded;shortcut.setAccessibilityIdentifier("snapliq.settings.screenshotShortcut")
        let row=NSStackView(views:[NSTextField(labelWithString:"截图快捷键"),shortcut]);row.spacing=18;root.addArrangedSubview(row)
        let warning=NSTextField(wrappingLabelWithString:"Command + X 是常用剪切键。启用为全局截图后会占用这一组合，影响其他应用的剪切。可在上方直接录入其他组合。")
        warning.font = .systemFont(ofSize:12);warning.textColor = .secondaryLabelColor;warning.preferredMaxLayoutWidth=480;root.addArrangedSubview(warning)
        recordingHotkeyToggle.target=self;recordingHotkeyToggle.action=#selector(toggleRecordingShortcut);root.addArrangedSubview(recordingHotkeyToggle)
        recordingShortcut.target=self;recordingShortcut.action=#selector(recordRecordingShortcut);recordingShortcut.bezelStyle = .rounded;recordingShortcut.setAccessibilityIdentifier("snapliq.settings.recordingShortcut")
        let recordingRow=NSStackView(views:[NSTextField(labelWithString:"录屏快捷键"),recordingShortcut]);recordingRow.spacing=18;root.addArrangedSubview(recordingRow)
        let recordingHint=NSTextField(wrappingLabelWithString:"按下即录制鼠标所在屏幕，再按一次停止并自动保存。首次使用可能需要系统权限；无需每次选择文件位置。全局快捷键会占用相同的应用内组合。")
        recordingHint.font = .systemFont(ofSize:12);recordingHint.textColor = .secondaryLabelColor;recordingHint.preferredMaxLayoutWidth=480;root.addArrangedSubview(recordingHint)
        systemAudioToggle.target=self;systemAudioToggle.action=#selector(toggleRecordingAudio);systemAudioToggle.setAccessibilityIdentifier("snapliq.settings.recordSystemAudio")
        microphoneToggle.target=self;microphoneToggle.action=#selector(toggleRecordingAudio);microphoneToggle.setAccessibilityIdentifier("snapliq.settings.recordMicrophone")
        if #available(macOS 15.0,*){}else{microphoneToggle.isEnabled=false;microphoneToggle.title="录制麦克风（需要 macOS 15 或更新版本）"}
        let audio=NSStackView(views:[systemAudioToggle,microphoneToggle]);audio.orientation = .vertical;audio.alignment = .leading;audio.spacing=8;root.addArrangedSubview(audio)
        let smart=NSButton(checkboxWithTitle:"智能框选窗口边界",target:self,action:#selector(toggleSmart(_:)))
        smart.state=Preferences.shared.defaults.bool(forKey:"smartSelection") ? .on:.off;root.addArrangedSubview(smart)
        let controls=NSButton(checkboxWithTitle:"识别应用内控件（需要辅助功能授权）",target:self,action:#selector(toggleControls(_:)))
        controls.state=Preferences.shared.defaults.bool(forKey:"smartControls") ? .on:.off;root.addArrangedSubview(controls)
        orbToggle.target=self;orbToggle.action=#selector(toggleOrb);root.addArrangedSubview(orbToggle)
        loginToggle.target=self;loginToggle.action=#selector(toggleLogin);root.addArrangedSubview(loginToggle)
        let choose=NSButton(title:"默认保存位置…",target:self,action:#selector(folderAction));choose.bezelStyle = .rounded
        folder.lineBreakMode = .byTruncatingMiddle;folder.font = .systemFont(ofSize:12);folder.textColor = .secondaryLabelColor
        folder.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let files=NSStackView(views:[choose,folder]);files.spacing=12;root.addArrangedSubview(files);files.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
        permission.font = .systemFont(ofSize:12);root.addArrangedSubview(permission)
        let capture=NSButton(title:"开始截图",target:self,action:#selector(captureAction));capture.bezelStyle = .rounded
        let record=NSButton(title:"快速录屏",target:self,action:#selector(quickRecordAction));record.bezelStyle = .rounded
        let perm=NSButton(title:"屏幕录制权限…",target:self,action:#selector(permissionAction));perm.bezelStyle = .rounded
        let actions=NSStackView(views:[capture,record,perm]);actions.spacing=12;root.addArrangedSubview(actions)
        let chrome=NSButton(title:"连接 Snapliq for Chrome…",target:self,action:#selector(connectChrome));chrome.bezelStyle = .rounded;root.addArrangedSubview(chrome)
        status.font = .systemFont(ofSize:12);status.textColor = .secondaryLabelColor;status.preferredMaxLayoutWidth=480;root.addArrangedSubview(status)
        shortcut.onRecord={ [weak self] e in self?.receive(e,kind:.screenshot) }
        recordingShortcut.onRecord={ [weak self] e in self?.receive(e,kind:.recording) };refresh()
    }
    required init?(coder:NSCoder){fatalError()}
    func present(){refresh();window?.center();showWindow(nil);NSApp.activate(ignoringOtherApps:true)}
    func refresh(){
        let p=Preferences.shared
        shortcut.title=shortcut.recording ? "请按组合键，Esc 取消":p.shortcutLabel+"  ·  修改"
        recordingShortcut.title=recordingShortcut.recording ? "请按组合键，Esc 取消":p.recordingShortcutLabel+"  ·  修改"
        hotkeyToggle.state=p.shortcutEnabled ? .on:.off
        recordingHotkeyToggle.state=p.recordingShortcutEnabled ? .on:.off
        systemAudioToggle.state=p.recordSystemAudio ? .on:.off;microphoneToggle.state=p.recordMicrophone ? .on:.off
        orbToggle.state=(!p.orbHidden && !p.orbDisabledToday) ? .on:.off
        loginToggle.state=SMAppService.mainApp.status == .enabled ? .on:.off
        folder.stringValue=p.folderURL?.path ?? (p.defaults.object(forKey:"folderBookmark") == nil ? "录屏默认：~/Movies/Snapliq":"保存位置失效，请重新选择")
        permission.stringValue=CGPreflightScreenCaptureAccess() ? "屏幕捕获权限：已授权":"屏幕捕获权限：首次截图或录屏时请求"
        status.stringValue="\(Product.version) 开发版 · 关闭此窗口后仍在菜单栏运行。\n方向键移动选区，Option + 方向键调整大小，Shift 加速。"
    }
    private func acceptConflict(key:UInt32,mods:UInt32,kind:HotkeyService.Kind = .screenshot)->Bool{
        guard key==UInt32(kVK_ANSI_X),mods==UInt32(cmdKey) else{return true}
        let operation=kind == .recording ? "录屏":"截图"
        let a=NSAlert();a.messageText="使用 Command + X 进行全局\(operation)？"
        a.informativeText="这会占用常用剪切快捷键，其他应用可能无法用 Command + X 剪切。Snapliq 不会同时无冲突地执行剪切和\(operation)。"
        a.addButton(withTitle:"启用并接受冲突");a.addButton(withTitle:"取消");return a.runModal() == .alertFirstButtonReturn
    }
    private func conflictsWithOther(key:UInt32,mods:UInt32,kind:HotkeyService.Kind)->Bool{
        let p=Preferences.shared
        return kind == .screenshot ? key==p.recordingShortcutKey && mods==p.recordingShortcutMods:key==p.shortcutKey && mods==p.shortcutMods
    }
    private func showDuplicate(){showError("截图与录屏需要不同的快捷键。请录入其他组合；即使其中一项未启用，也不能使用相同组合。")}
    @discardableResult private func restoreHotkeys()->(OSStatus,OSStatus){(onHotkeyChanged?() ?? 0,onRecordingHotkeyChanged?() ?? 0)}
    private func endShortcutRecording(){
        guard shortcut.recording || recordingShortcut.recording else{return}
        shortcut.recording=false;recordingShortcut.recording=false;_ = restoreHotkeys();refresh()
    }
    @objc func toggleShortcut(){
        let enabled=hotkeyToggle.state == .on;endShortcutRecording()
        let p=Preferences.shared
        if enabled,conflictsWithOther(key:p.shortcutKey,mods:p.shortcutMods,kind:.screenshot){showDuplicate();refresh();return}
        if enabled,!acceptConflict(key:p.shortcutKey,mods:p.shortcutMods){refresh();return}
        p.shortcutEnabled=enabled
        let result=onHotkeyChanged?() ?? 0
        if result != 0{p.shortcutEnabled=false;showError("截图快捷键注册失败（\(result)），可能已被其他应用占用。请录入其他组合。")}
        refresh()
    }
    @objc func toggleRecordingShortcut(){
        let enabled=recordingHotkeyToggle.state == .on;endShortcutRecording()
        let p=Preferences.shared
        if enabled,conflictsWithOther(key:p.recordingShortcutKey,mods:p.recordingShortcutMods,kind:.recording){showDuplicate();refresh();return}
        if enabled,!acceptConflict(key:p.recordingShortcutKey,mods:p.recordingShortcutMods,kind:.recording){refresh();return}
        p.recordingShortcutEnabled=enabled
        let result=onRecordingHotkeyChanged?() ?? 0
        if result != 0{p.recordingShortcutEnabled=false;showError("录屏快捷键注册失败（\(result)），可能已被其他应用占用。请录入其他组合。")}
        refresh()
    }
    @objc func recordShortcut(){beginShortcutRecording(.screenshot)}
    @objc func recordRecordingShortcut(){beginShortcutRecording(.recording)}
    private func beginShortcutRecording(_ kind:HotkeyService.Kind){
        shortcut.recording=false;recordingShortcut.recording=false;onSuspendHotkey?()
        let recorder=kind == .screenshot ? shortcut:recordingShortcut
        recorder.recording=true;recorder.title="请按组合键，Esc 取消";window?.makeFirstResponder(recorder);refresh()
    }
    private func receive(_ event:NSEvent,kind:HotkeyService.Kind){
        if event.keyCode==53{endShortcutRecording();return}
        let f=event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard f.contains(.command)||f.contains(.option)||f.contains(.control) else{NSSound.beep();return}
        var mods:UInt32=0,label=""
        if f.contains(.control){mods|=UInt32(controlKey);label+="⌃"}
        if f.contains(.option){mods|=UInt32(optionKey);label+="⌥"}
        if f.contains(.shift){mods|=UInt32(shiftKey);label+="⇧"}
        if f.contains(.command){mods|=UInt32(cmdKey);label+="⌘"}
        label+=" "+(event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)")
        let key=UInt32(event.keyCode),p=Preferences.shared,isRecording=kind == .recording
        if conflictsWithOther(key:key,mods:mods,kind:kind){showDuplicate();return}
        if (isRecording ? p.recordingShortcutEnabled:p.shortcutEnabled) && !acceptConflict(key:key,mods:mods,kind:kind){return}
        let oldKey=isRecording ? p.recordingShortcutKey:p.shortcutKey,oldMods=isRecording ? p.recordingShortcutMods:p.shortcutMods,oldLabel=isRecording ? p.recordingShortcutLabel:p.shortcutLabel
        if isRecording{p.recordingShortcutKey=key;p.recordingShortcutMods=mods;p.recordingShortcutLabel=label}
        else{p.shortcutKey=key;p.shortcutMods=mods;p.shortcutLabel=label}
        shortcut.recording=false;recordingShortcut.recording=false
        let results=restoreHotkeys(),result=isRecording ? results.1:results.0
        if result != 0{
            if isRecording{p.recordingShortcutKey=oldKey;p.recordingShortcutMods=oldMods;p.recordingShortcutLabel=oldLabel}
            else{p.shortcutKey=oldKey;p.shortcutMods=oldMods;p.shortcutLabel=oldLabel}
            _ = restoreHotkeys();showError("该组合注册失败（\(result)），已恢复原快捷键。")
        }
        refresh()
    }
    @objc func toggleRecordingAudio(){
        Preferences.shared.recordSystemAudio=systemAudioToggle.state == .on
        if #available(macOS 15.0,*){Preferences.shared.recordMicrophone=microphoneToggle.state == .on}
        onRecordingPreferencesChanged?()
    }
    @objc func toggleSmart(_ sender:NSButton){Preferences.shared.defaults.set(sender.state == .on,forKey:"smartSelection")}
    @objc func toggleControls(_ sender:NSButton){
        let enabled=sender.state == .on
        if enabled{_ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary)}
        Preferences.shared.defaults.set(enabled,forKey:"smartControls")
    }
    @objc func toggleOrb(){if orbToggle.state == .on{Preferences.shared.restoreOrb()}else{Preferences.shared.orbHidden=true};onOrbChanged?();refresh()}
    @objc func toggleLogin(){
        do{if loginToggle.state == .on{try SMAppService.mainApp.register()}else{try SMAppService.mainApp.unregister()}}catch{showError("启动项设置失败：\(error.localizedDescription)")};refresh()
    }
    @objc func folderAction(){_ = chooseFolder()}
    func chooseFolder()->URL?{
        let p=NSOpenPanel();p.title="选择 Snapliq 默认保存文件夹";p.canChooseFiles=false;p.canChooseDirectories=true;p.canCreateDirectories=true;p.directoryURL=Preferences.shared.folderURL
        guard p.runModal() == .OK,let u=p.url else{return nil}
        do{try Preferences.shared.setFolder(u);refresh();return u}catch{showError(error.localizedDescription);return nil}
    }
    @objc func connectChrome(){
        do{_ = try DesktopBridge.registerChromeHost();status.stringValue="浏览器接口已登记到当前应用。请加载 Snapliq for Chrome 扩展；退出 Chrome 后桌面工具仍独立运行。"}
        catch{showError(error.localizedDescription)}
    }
    @objc func permissionAction(){if !CGPreflightScreenCaptureAccess(){_ = CGRequestScreenCaptureAccess()};NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)}
    @objc func captureAction(){endShortcutRecording();window?.orderOut(nil);onCapture?()}
    @objc func quickRecordAction(){endShortcutRecording();window?.orderOut(nil);onQuickRecord?()}
    func windowWillClose(_ notification:Notification){endShortcutRecording();Metrics.shared.write("settings_closed",["applicationContinues":true])}
}
