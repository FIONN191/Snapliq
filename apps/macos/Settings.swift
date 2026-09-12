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
final class SettingsController:NSWindowController,NSWindowDelegate {
    var onCapture:(()->Void)?
    var onOrbChanged:(()->Void)?
    var onHotkeyChanged:(()->OSStatus)?
    var onSuspendHotkey:(()->Void)?
    private let shortcut=ShortcutRecorder(title:"",target:nil,action:nil)
    private let hotkeyToggle=NSButton(checkboxWithTitle:"启用全局截图快捷键",target:nil,action:nil)
    private let orbToggle=NSButton(checkboxWithTitle:"显示桌面悬浮球",target:nil,action:nil)
    private let loginToggle=NSButton(checkboxWithTitle:"登录时启动 Snapliq",target:nil,action:nil)
    private let folder=NSTextField(labelWithString:"尚未设置")
    private let permission=NSTextField(labelWithString:"")
    private let status=NSTextField(wrappingLabelWithString:"")
    init(){
        let w=NSWindow(contentRect:.init(x:0,y:0,width:550,height:685),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        w.title="\(Product.name) 设置";w.isReleasedWhenClosed=false
        super.init(window:w);w.delegate=self
        let root=NSStackView();root.orientation = .vertical;root.alignment = .leading;root.spacing=16
        root.translatesAutoresizingMaskIntoConstraints=false;w.contentView!.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:w.contentView!.leadingAnchor,constant:30),root.trailingAnchor.constraint(equalTo:w.contentView!.trailingAnchor,constant:-30),root.topAnchor.constraint(equalTo:w.contentView!.topAnchor,constant:25)])
        let title=NSTextField(labelWithString:Product.name);title.font = .systemFont(ofSize:28,weight:.semibold)
        let subtitle=NSTextField(labelWithString:Product.tagline);subtitle.textColor = .secondaryLabelColor
        root.addArrangedSubview(title);root.addArrangedSubview(subtitle)
        hotkeyToggle.target=self;hotkeyToggle.action=#selector(toggleShortcut);root.addArrangedSubview(hotkeyToggle)
        shortcut.target=self;shortcut.action=#selector(recordShortcut);shortcut.bezelStyle = .rounded
        let row=NSStackView(views:[NSTextField(labelWithString:"截图快捷键"),shortcut]);row.spacing=18;root.addArrangedSubview(row)
        let warning=NSTextField(wrappingLabelWithString:"Command + X 是常用剪切键。启用为全局截图后会占用这一组合，影响其他应用的剪切。可在上方直接录入其他组合。")
        warning.font = .systemFont(ofSize:12);warning.textColor = .secondaryLabelColor;warning.preferredMaxLayoutWidth=480;root.addArrangedSubview(warning)
        let smart=NSButton(checkboxWithTitle:"智能框选窗口边界",target:self,action:#selector(toggleSmart(_:)))
        smart.state=Preferences.shared.defaults.bool(forKey:"smartSelection") ? .on:.off;root.addArrangedSubview(smart)
        let controls=NSButton(checkboxWithTitle:"识别应用内控件（需要辅助功能授权）",target:self,action:#selector(toggleControls(_:)))
        controls.state=Preferences.shared.defaults.bool(forKey:"smartControls") ? .on:.off;root.addArrangedSubview(controls)
        orbToggle.target=self;orbToggle.action=#selector(toggleOrb);root.addArrangedSubview(orbToggle)
        loginToggle.target=self;loginToggle.action=#selector(toggleLogin);root.addArrangedSubview(loginToggle)
        let choose=NSButton(title:"默认保存位置…",target:self,action:#selector(folderAction));choose.bezelStyle = .rounded
        folder.lineBreakMode = .byTruncatingMiddle;folder.font = .systemFont(ofSize:12);folder.textColor = .secondaryLabelColor
        let files=NSStackView(views:[choose,folder]);files.spacing=12;root.addArrangedSubview(files)
        permission.font = .systemFont(ofSize:12);root.addArrangedSubview(permission)
        let capture=NSButton(title:"开始截图",target:self,action:#selector(captureAction));capture.bezelStyle = .rounded
        let perm=NSButton(title:"屏幕录制权限…",target:self,action:#selector(permissionAction));perm.bezelStyle = .rounded
        let actions=NSStackView(views:[capture,perm]);actions.spacing=12;root.addArrangedSubview(actions)
        let chrome=NSButton(title:"连接 Snapliq for Chrome…",target:self,action:#selector(connectChrome));chrome.bezelStyle = .rounded;root.addArrangedSubview(chrome)
        status.font = .systemFont(ofSize:12);status.textColor = .secondaryLabelColor;status.preferredMaxLayoutWidth=480;root.addArrangedSubview(status)
        shortcut.onRecord={ [weak self] e in self?.receive(e) };refresh()
    }
    required init?(coder:NSCoder){fatalError()}
    func present(){refresh();window?.center();showWindow(nil);NSApp.activate(ignoringOtherApps:true)}
    func refresh(){
        let p=Preferences.shared
        shortcut.title=shortcut.recording ? "请按组合键，Esc 取消":p.shortcutLabel+"  ·  修改"
        hotkeyToggle.state=p.shortcutEnabled ? .on:.off
        orbToggle.state=(!p.orbHidden && !p.orbDisabledToday) ? .on:.off
        loginToggle.state=SMAppService.mainApp.status == .enabled ? .on:.off
        folder.stringValue=p.folderURL?.path ?? "尚未设置 / 位置需重新授权"
        permission.stringValue=CGPreflightScreenCaptureAccess() ? "屏幕捕获权限：已授权":"屏幕捕获权限：首次截图时请求"
        status.stringValue="\(Product.version) 开发版 · 关闭此窗口后仍在菜单栏运行。\n方向键移动选区，Option + 方向键调整大小，Shift 加速。"
    }
    private func acceptConflict(key:UInt32,mods:UInt32)->Bool{
        guard key==7,mods==UInt32(cmdKey) else{return true}
        let a=NSAlert();a.messageText="使用 Command + X 进行全局截图？"
        a.informativeText="这会占用常用剪切快捷键，其他应用可能无法用 Command + X 剪切。Snapliq 不会同时无冲突地执行剪切和截图。"
        a.addButton(withTitle:"启用并接受冲突");a.addButton(withTitle:"取消");return a.runModal() == .alertFirstButtonReturn
    }
    @objc func toggleShortcut(){
        let p=Preferences.shared
        if hotkeyToggle.state == .on,!acceptConflict(key:p.shortcutKey,mods:p.shortcutMods){refresh();return}
        p.shortcutEnabled=hotkeyToggle.state == .on
        let result=onHotkeyChanged?() ?? 0
        if result != 0{p.shortcutEnabled=false;showError("快捷键注册失败（\(result)），可能已被其他应用占用。请录入其他组合。")}
        refresh()
    }
    @objc func recordShortcut(){onSuspendHotkey?();shortcut.recording=true;shortcut.title="请按组合键，Esc 取消";window?.makeFirstResponder(shortcut)}
    private func receive(_ event:NSEvent){
        if event.keyCode==53{shortcut.recording=false;_ = onHotkeyChanged?();refresh();return}
        let f=event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard f.contains(.command)||f.contains(.option)||f.contains(.control) else{NSSound.beep();return}
        var mods:UInt32=0,label=""
        if f.contains(.control){mods|=UInt32(controlKey);label+="⌃"}
        if f.contains(.option){mods|=UInt32(optionKey);label+="⌥"}
        if f.contains(.shift){mods|=UInt32(shiftKey);label+="⇧"}
        if f.contains(.command){mods|=UInt32(cmdKey);label+="⌘"}
        label+=" "+(event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)")
        if Preferences.shared.shortcutEnabled && !acceptConflict(key:UInt32(event.keyCode),mods:mods){return}
        let p=Preferences.shared,oldKey=p.shortcutKey,oldMods=p.shortcutMods,oldLabel=p.shortcutLabel
        p.shortcutKey=UInt32(event.keyCode);p.shortcutMods=mods;p.shortcutLabel=label;shortcut.recording=false
        let result=onHotkeyChanged?() ?? 0
        if result != 0{p.shortcutKey=oldKey;p.shortcutMods=oldMods;p.shortcutLabel=oldLabel;_ = onHotkeyChanged?();showError("该组合注册失败（\(result)），已恢复原快捷键。")}
        refresh()
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
    @objc func captureAction(){window?.orderOut(nil);onCapture?()}
    func windowWillClose(_ notification:Notification){if shortcut.recording{shortcut.recording=false;_ = onHotkeyChanged?()};Metrics.shared.write("settings_closed",["applicationContinues":true])}
}
