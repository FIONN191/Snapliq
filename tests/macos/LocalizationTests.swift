import AppKit

/// Runs against a dedicated test bundle and temporary preferences suites. No real
/// screen capture, global shortcuts, microphone, or clipboard access is needed.
@main struct LocalizationTests {
    static func require(_ condition:Bool,_ message:String)throws {
        if !condition {throw NSError(domain:"LocalizationTests",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
    }
    static func storeTests()throws {
        let suite="com.snapliq.tests.localization."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        let store=LocalizationStore(defaults:defaults)
        try require(store.language == .chinese,"Existing users must retain the Chinese default")
        defaults.set(false,forKey:"recordMicrophone")
        defaults.set(true,forKey:"recordSystemAudio")
        defaults.set(72,forKey:"orbSize")
        defaults.set("custom shortcut",forKey:"shortcutLabel")
        var changes=[AppLanguage](),allOnMain=true
        let observer=NotificationCenter.default.addObserver(forName:.snapliqLanguageChanged,object:store,queue:nil){_ in
            changes.append(store.language);allOnMain = allOnMain && Thread.isMainThread
        }
        defer{NotificationCenter.default.removeObserver(observer)}
        store.language = .english
        store.language = .english
        try require(changes == [.english],"A language change must notify once, after saving the new language")
        try require(store.text("截图","Screenshot")=="Screenshot","English text selection failed")
        defaults.synchronize()
        let child=Process()
        child.executableURL=Bundle.main.executableURL
        child.arguments=["--probe-persisted",suite,"en"]
        try child.run();child.waitUntilExit()
        try require(child.terminationStatus==0,"Language choice was not retained across process restart")
        store.language = .chinese
        try require(changes == [.english,.chinese],"Switching back must notify observers")
        try require(store.text("截图","Screenshot")=="截图","Chinese text selection failed")
        try require(!defaults.bool(forKey:"recordMicrophone"),"Changing language altered microphone preference")
        try require(defaults.bool(forKey:"recordSystemAudio"),"Changing language altered system audio preference")
        try require(defaults.integer(forKey:"orbSize")==72,"Changing language altered floating button size")
        try require(defaults.string(forKey:"shortcutLabel")=="custom shortcut","Changing language altered shortcut preference")
        let invalidPreferences:[Any] = ["fr","",42]
        for invalid in invalidPreferences {
            defaults.set(invalid,forKey:"interfaceLanguage")
            try require(LocalizationStore(defaults:defaults).language == .chinese,"An unknown or malformed preference must fall back to Chinese")
        }
        DispatchQueue.global().async{store.language = .english}
        let deadline=Date().addingTimeInterval(3)
        while changes.count<3 && Date()<deadline {RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
        try require(changes == [.english,.chinese,.english] && allOnMain,"Background language changes must reach UI observers on the main thread")
        print("PASS localization preferences: default, both languages, process restart, malformed-value fallback, unrelated settings, main-thread notifications")
    }
    @MainActor static func main(){
        if let index=CommandLine.arguments.firstIndex(of:"--probe-persisted"),CommandLine.arguments.count>index+2 {
            let store=LocalizationStore(defaults:UserDefaults(suiteName:CommandLine.arguments[index+1])!)
            exit(store.language.rawValue==CommandLine.arguments[index+2] ? 0:1)
        }
        do{try storeTests()}catch{fputs("FAIL localization: \(error.localizedDescription)\n",stderr);exit(1)}
        #if LOCALIZATION_UI
        guard CommandLine.arguments.contains("--run-ui") else{return}
        let app=NSApplication.shared;app.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            Task { @MainActor in
                do{try await uiTests();exit(0)}catch{fputs("FAIL localization UI: \(error.localizedDescription)\n",stderr);exit(1)}
            }
        }
        app.run()
        #endif
    }

    #if LOCALIZATION_UI
    @MainActor static func descendants(_ root:NSView)->[NSView]{[root]+root.subviews.flatMap{descendants($0)}}
    @MainActor static func views(_ window:NSWindow)->[NSView]{window.contentView.map{descendants($0)} ?? []}
    @MainActor static func control<T:NSView>(_ window:NSWindow,_ id:String,as:T.Type)throws->T {
        guard let view=views(window).first(where:{$0.accessibilityIdentifier()==id}) as? T else {
            throw NSError(domain:"LocalizationTests",code:2,userInfo:[NSLocalizedDescriptionKey:"Missing control: "+id])
        }
        return view
    }
    @MainActor static func checkButtonLayout(_ window:NSWindow)throws {
        guard let root=window.contentView else{return};root.layoutSubtreeIfNeeded()
        for button in views(window).compactMap({$0 as? NSButton}) where !button.isHidden {
            let rect=button.convert(button.bounds,to:root)
            try require(rect.width+0.5>=button.intrinsicContentSize.width && root.bounds.insetBy(dx:-0.5,dy:-0.5).contains(rect),"Clipped localized button: "+button.title)
        }
    }
    @MainActor static func renderSettings(_ window:NSWindow,language:AppLanguage)throws {
        guard let root=window.contentView else{return}
        window.appearance=NSAppearance(named:.aqua)
        root.layoutSubtreeIfNeeded()
        let document=views(window).compactMap{$0 as? NSScrollView}.first?.documentView ?? root
        document.layoutSubtreeIfNeeded()
        guard let bitmap=document.bitmapImageRepForCachingDisplay(in:document.bounds) else{throw NSError(domain:"LocalizationTests",code:7)}
        document.cacheDisplay(in:document.bounds,to:bitmap)
        // A scroll document has no opaque background of its own. Supply a test-only
        // backing so exported snapshots remain legible in dark image viewers.
        let rendered=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:bitmap.pixelsWide,pixelsHigh:bitmap.pixelsHigh,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        let canvas=NSRect(x:0,y:0,width:rendered.pixelsWide,height:rendered.pixelsHigh)
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rendered)
        NSColor.white.setFill();canvas.fill()
        NSImage(cgImage:bitmap.cgImage!,size:canvas.size).draw(in:canvas,from:.zero,operation:.sourceOver,fraction:1)
        NSGraphicsContext.restoreGraphicsState()
        let directory=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("work/localization-tests",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        guard let png=rendered.representation(using:.png,properties:[:]) else{throw NSError(domain:"LocalizationTests",code:8)}
        try png.write(to:directory.appendingPathComponent("settings-\(language.rawValue).png"))
    }
    @MainActor static func uiTests()async throws {
        // Refuse to touch standard defaults unless the script supplied its own bundle.
        let domain="com.snapliq.tests.localization"
        try require(Bundle.main.bundleIdentifier==domain,"UI checks must run from their isolated test bundle")
        let defaults=UserDefaults.standard,saved=UserDefaults.standard.persistentDomain(forName:domain)
        defaults.removePersistentDomain(forName:domain)
        defer{
            defaults.removePersistentDomain(forName:domain)
            if let saved=saved{defaults.setPersistentDomain(saved,forName:domain)}
            defaults.synchronize()
        }
        Localization.shared.language = .chinese
        let settings=SettingsController()
        guard let settingsWindow=settings.window else{throw NSError(domain:"LocalizationTests",code:3)}
        defer{settingsWindow.close()}
        let language=try control(settingsWindow,"snapliq.settings.language",as:NSPopUpButton.self)
        let prefs=Preferences.shared
        prefs.recordMicrophone=false;prefs.recordSystemAudio=true;prefs.orbSize=72
        language.selectItem(at:1)
        try require(language.sendAction(language.action,to:language.target),"Language menu action did not reach settings")
        try require(Localization.shared.language == .english && settings.window === settingsWindow,"Settings language action must refresh the same window immediately")
        try require(!prefs.recordMicrophone && prefs.recordSystemAudio && prefs.orbSize==72,"Settings refresh overwrote user preferences")
        try require(settingsWindow.title.contains("Settings"),"Settings window title did not switch to English")
        try renderSettings(settingsWindow,language:.english)
        let shortcut=try control(settingsWindow,"snapliq.settings.screenshotShortcut",as:ShortcutRecorder.self)
        let previousShortcut=prefs.shortcutLabel,previousKey=prefs.shortcutKey,previousModifiers=prefs.shortcutMods
        var suspended=0,restored=0
        settings.onSuspendHotkey={suspended+=1}
        settings.onHotkeyChanged={restored+=1;return 0}
        settings.recordShortcut()
        Localization.shared.language = .chinese
        try require(shortcut.recording && suspended==1 && restored==0 && shortcut.title=="请按组合键，Esc 取消","Changing language ended an unfinished shortcut edit")
        try require(prefs.shortcutLabel==previousShortcut && prefs.shortcutKey==previousKey && prefs.shortcutMods==previousModifiers,"Changing language saved an unfinished shortcut")
        // Cancel directly within this test window; no global keyboard event is posted.
        let escape=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:settingsWindow.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!
        shortcut.keyDown(with:escape)
        try require(!shortcut.recording && restored==1,"The pending shortcut edit must remain cancellable")
        try renderSettings(settingsWindow,language:.chinese)

        guard let screen=NSScreen.main else{throw NSError(domain:"LocalizationTests",code:4)}
        let frame=screen.frame,size=frame.size,scale=screen.backingScaleFactor
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width*scale),pixelsHigh:Int(size.height*scale),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
        NSColor.white.setFill();NSRect(x:0,y:0,width:size.width*scale,height:size.height*scale).fill()
        ("Capture 123" as NSString).draw(at:.init(x:100,y:200),withAttributes:[.font:NSFont.systemFont(ofSize:64),.foregroundColor:NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        let snapshot=DisplaySnapshot(id:1,frame:frame,image:bitmap.cgImage!,capturedAt:now())
        let session=SelectionSession(snapshots:[snapshot],started:now(),mode:.screen,candidates:[])
        var finishes=0;session.onFinish={_ in finishes+=1};session.present()
        defer{session.cancel()}
        let selection=frame.insetBy(dx:100,dy:100);session.selection=selection
        let overlays=NSApp.windows.filter{$0 is SelectionWindow}
        for selectedLanguage:AppLanguage in [.english,.chinese,.english] {
            Localization.shared.language=selectedLanguage
            try require(session.selection==selection && finishes==0,"Language change must preserve the live selection")
            try require(overlays.allSatisfy{original in NSApp.windows.contains{$0 === original && $0.isVisible}},"Language change replaced or hid a capture overlay")
            let panels=NSApp.windows.filter{$0.isVisible && !($0 is SelectionWindow)}
            let extract=panels.flatMap{views($0)}.compactMap{$0 as? NSButton}.first{$0.accessibilityIdentifier()=="snapliq.selection.extractText"}
            try require(extract?.title==(selectedLanguage == .english ? "Extract Text":"提取文字"),"Selection toolbar did not refresh language")
            for panel in panels{try checkButtonLayout(panel)}
        }
        session.cancel()

        let ocr=OCRPanel(image:bitmap.cgImage!)
        guard let ocrWindow=ocr.window else{throw NSError(domain:"LocalizationTests",code:5)}
        defer{ocrWindow.close()}
        let text=try control(ocrWindow,"snapliq.ocr.text",as:NSTextView.self)
        let ocrStatus=try control(ocrWindow,"snapliq.ocr.status",as:NSTextField.self)
        for _ in 0..<150 {
            if ocrStatus.stringValue != "Recognizing Chinese and English on this Mac…"{break}
            try await Task.sleep(nanoseconds:100_000_000)
        }
        try require(ocrStatus.stringValue=="Ready to edit and copy." && text.string.contains("123"),"Generated-image OCR did not finish: \(ocrStatus.stringValue); text=\(text.string)")
        let edit="My edited OCR result\n用户编辑的文字";text.string=edit;text.setSelectedRange(NSRange(location:3,length:5))
        Localization.shared.language = .chinese
        Localization.shared.language = .english
        try require(ocr.window === ocrWindow && text.string==edit && text.selectedRange()==NSRange(location:3,length:5),"Language refresh must preserve edited OCR text and selection")
        try require(try control(ocrWindow,"snapliq.ocr.copy",as:NSButton.self).title=="Copy Text","OCR actions did not refresh language")
        try checkButtonLayout(ocrWindow)

        // Exercise control rendering, without starting a stream or touching audio devices.
        let recording=RecordingController(),recordingUI=RecordingUI(controller:recording)
        defer{recordingUI.update(.idle)}
        recordingUI.update(.paused)
        guard let panel=NSApp.windows.first(where:{$0.accessibilityIdentifier()=="snapliq.recording.controls"}) else{throw NSError(domain:"LocalizationTests",code:6)}
        let pause=try control(panel,"snapliq.recording.pause",as:NSButton.self)
        Localization.shared.language = .chinese
        try require(pause.title=="继续" && panel.isVisible,"Paused controls did not switch to Chinese")
        Localization.shared.language = .english
        try require(pause.title=="Resume" && panel.isVisible,"Paused controls did not switch to English")
        recordingUI.update(.recording)
        Localization.shared.language = .chinese;Localization.shared.language = .english
        try require(pause.title=="Pause" && panel.isVisible && recording.state == .idle,"Language refresh must preserve controls without starting native recording")
        try checkButtonLayout(panel)
        print("PASS isolated localization UI: same settings window, preserved selection and overlays, English/Chinese toolbar layout, editable OCR preservation, recording-control state rendering; no real recording was started")
    }
    #endif
}
