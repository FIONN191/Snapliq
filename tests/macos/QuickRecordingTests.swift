import AppKit
import Carbon

/// Runs without screen/microphone access, global shortcut registration, or user preferences.
@main struct QuickRecordingTests {
    static var checks=0
    static func expect(_ condition:@autoclosure ()->Bool,_ message:String){
        checks+=1
        precondition(condition(),message)
    }
    static func reject(_ message:String,_ body:() throws->Void){
        checks+=1
        do{try body();preconditionFailure(message)}catch{}
    }
    @MainActor static func drainCallbacks()async{
        await withCheckedContinuation{continuation in DispatchQueue.main.async{continuation.resume()}}
    }
    @MainActor static func send(_ kind:UInt32,_ id:UInt32,signature:OSType=0x534e4150)throws->OSStatus{
        var event:EventRef?
        let status=CreateEvent(nil,OSType(kEventClassKeyboard),kind,GetCurrentEventTime(),EventAttributes(kEventAttributeNone),&event)
        guard status==noErr,let event=event else{throw NSError(domain:NSOSStatusErrorDomain,code:Int(status))}
        defer{ReleaseEvent(event)}
        var identifier=EventHotKeyID(signature:signature,id:id)
        let parameterStatus=SetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),MemoryLayout<EventHotKeyID>.size,&identifier)
        guard parameterStatus==noErr else{throw NSError(domain:NSOSStatusErrorDomain,code:Int(parameterStatus))}
        return SendEventToEventTarget(event,GetApplicationEventTarget())
    }
    @MainActor static func main()async throws{
        _ = NSApplication.shared
        let fm=FileManager.default,suite="Snapliq.QuickRecordingTests."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defaults.removePersistentDomain(forName:suite)
        let temporary=fm.temporaryDirectory.appendingPathComponent(suite,isDirectory:true)
        try fm.createDirectory(at:temporary,withIntermediateDirectories:true)
        defer{defaults.removePersistentDomain(forName:suite);try? fm.removeItem(at:temporary)}
        let preferences=Preferences(defaults:defaults)

        expect(preferences.recordingShortcutEnabled,"Recording shortcut should start enabled")
        expect(preferences.recordingShortcutKey==15,"Recording shortcut should use R")
        expect(preferences.recordingShortcutMods==UInt32(cmdKey|optionKey),"Recording shortcut should use Option + Command")
        expect(preferences.recordingShortcutLabel=="⌥⌘ R","Recording shortcut label should match its actual combination")
        expect(preferences.recordSystemAudio,"System audio should default on")
        expect(preferences.recordMicrophone,"Microphone should default on")
        expect(!preferences.shortcutEnabled,"Existing screenshot consent default must remain disabled")
        expect(preferences.shortcutKey==7,"Screenshot shortcut must remain X")
        expect(preferences.shortcutMods==UInt32(cmdKey),"Screenshot shortcut must remain Command")
        expect(preferences.shortcutLabel=="⌘ X","Screenshot shortcut label must remain unchanged")
        preferences.recordingShortcutEnabled=false
        preferences.recordSystemAudio=false
        preferences.recordMicrophone=false
        let reopened=Preferences(defaults:defaults)
        expect(!reopened.recordingShortcutEnabled,"Explicit recording shortcut disable must survive reopening")
        expect(!reopened.recordSystemAudio,"Explicit system audio opt-out must survive reopening")
        expect(!reopened.recordMicrophone,"Explicit microphone opt-out must survive reopening")
        preferences.shortcutEnabled=true;preferences.shortcutKey=8
        preferences.shortcutMods=UInt32(cmdKey|shiftKey);preferences.shortcutLabel="⇧⌘ C"
        preferences.recordingShortcutEnabled=true;preferences.recordingShortcutKey=17
        preferences.recordingShortcutMods=UInt32(cmdKey|controlKey);preferences.recordingShortcutLabel="⌃⌘ T"
        expect(reopened.recordingShortcutEnabled,"Recording enable update must persist")
        expect(reopened.recordingShortcutKey==17,"Custom recording key must persist")
        expect(reopened.recordingShortcutMods==UInt32(cmdKey|controlKey),"Custom recording modifiers must persist")
        expect(reopened.recordingShortcutLabel=="⌃⌘ T","Custom recording label must persist")
        expect(reopened.shortcutEnabled && reopened.shortcutKey==8 && reopened.shortcutMods==UInt32(cmdKey|shiftKey) && reopened.shortcutLabel=="⇧⌘ C","Recording settings must leave the screenshot shortcut independent")
        print("PASS preferences: \(checks) checks; new defaults, explicit opt-outs, custom combinations and legacy screenshot settings")
        let preferenceChecks=checks

        let movies=temporary.appendingPathComponent("Movies",isDirectory:true)
        let fixedDate=Date(timeIntervalSince1970:1_800_000_000)
        let first=try RecordingDestination.makeURL(preferences:preferences,moviesDirectory:movies,date:fixedDate,identifier:"stable-id")
        var isDirectory:ObjCBool=false
        expect(fm.fileExists(atPath:first.deletingLastPathComponent().path,isDirectory:&isDirectory) && isDirectory.boolValue,"First recording must create Movies/Snapliq")
        expect(first.deletingLastPathComponent()==movies.appendingPathComponent(Product.name,isDirectory:true),"No bookmark must use Movies/Snapliq")
        expect(first.pathExtension=="mp4" && first.lastPathComponent.hasPrefix(Product.name+"-") && first.lastPathComponent.hasSuffix("-stable-id.mp4"),"Automatic filename must identify the product and MP4 format")
        expect(!fm.fileExists(atPath:first.path),"Choosing a destination must not create an empty final recording")
        let original=Data("existing recording".utf8),secondBytes=Data("second recording".utf8)
        try original.write(to:first)
        let second=try RecordingDestination.makeURL(preferences:preferences,moviesDirectory:movies,date:fixedDate,identifier:"stable-id")
        expect(second.lastPathComponent==first.deletingPathExtension().lastPathComponent+"-2.mp4","First collision must add a deterministic suffix")
        try secondBytes.write(to:second)
        let third=try RecordingDestination.makeURL(preferences:preferences,moviesDirectory:movies,date:fixedDate,identifier:"stable-id")
        expect(third.lastPathComponent==first.deletingPathExtension().lastPathComponent+"-3.mp4","Repeated collisions must advance the suffix")
        let firstBytes=try Data(contentsOf:first),retainedSecond=try Data(contentsOf:second)
        expect(firstBytes==original && retainedSecond==secondBytes,"Choosing a new recording must preserve existing recordings")
        expect(!fm.fileExists(atPath:third.path),"Collision handling must not precreate the new file")

        let selected=temporary.appendingPathComponent("Selected folder",isDirectory:true)
        try fm.createDirectory(at:selected,withIntermediateDirectories:true)
        try preferences.setFolder(selected)
        let unusedMovies=temporary.appendingPathComponent("UnusedMovies",isDirectory:true)
        let chosen=try RecordingDestination.makeURL(preferences:preferences,moviesDirectory:unusedMovies,date:fixedDate,identifier:"bookmark")
        expect(chosen.deletingLastPathComponent().standardizedFileURL==selected.standardizedFileURL,"A selected folder bookmark must be honored")
        expect(!fm.fileExists(atPath:unusedMovies.path),"A selected folder must not create the fallback location")
        defaults.set(Data([0,1,2,3]),forKey:"folderBookmark")
        reject("A corrupt bookmark must be surfaced instead of silently saving elsewhere"){
            _ = try RecordingDestination.makeURL(preferences:preferences,moviesDirectory:unusedMovies)
        }
        expect(!fm.fileExists(atPath:unusedMovies.path),"A corrupt bookmark must not silently use Movies")
        let regularFile=temporary.appendingPathComponent("not-a-directory")
        try Data("keep".utf8).write(to:regularFile)
        try preferences.setFolder(regularFile)
        reject("A file bookmark cannot serve as a recording folder"){
            _ = try RecordingDestination.makeURL(preferences:preferences,moviesDirectory:unusedMovies)
        }
        defaults.removeObject(forKey:"folderBookmark")
        reject("An unusable Movies path must produce an error"){
            _ = try RecordingDestination.makeURL(preferences:preferences,moviesDirectory:regularFile)
        }
        let retainedFile=try Data(contentsOf:regularFile)
        expect(retainedFile==Data("keep".utf8),"A folder creation failure must not replace an existing file")
        try preferences.setFolder(selected)
        try fm.setAttributes([.posixPermissions:0o555],ofItemAtPath:selected.path)
        defer{try? fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:selected.path)}
        if geteuid() != 0 {
            reject("A read-only selected folder must fail before capture begins"){
                _ = try RecordingDestination.makeURL(preferences:preferences,moviesDirectory:unusedMovies)
            }
        } else {print("SKIP read-only folder permission check: root bypasses POSIX permissions")}
        try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:selected.path)
        try fm.removeItem(at:selected)
        reject("A deleted selected folder must be reported as unavailable"){
            _ = try RecordingDestination.makeURL(preferences:preferences,moviesDirectory:unusedMovies)
        }
        print("PASS automatic destinations: \(checks-preferenceChecks) checks; default directory, bookmarks, collisions, existing data and unavailable paths")
        let destinationChecks=checks

        // Exercise actual installed Carbon handlers without registering or pressing global shortcuts.
        // Carbon routes the uppermost handler first; each handler must ignore the other action's ID.
        let screenshot=HotkeyService(kind:.screenshot,preferences:preferences)
        let recording=HotkeyService(kind:.recording,preferences:preferences)
        var screenshotTriggers=0,recordingTriggers=0
        screenshot.onTrigger={screenshotTriggers+=1};recording.onTrigger={recordingTriggers+=1}
        let pressed=UInt32(kEventHotKeyPressed),released=UInt32(kEventHotKeyReleased)
        var status=try send(pressed,1)
        await drainCallbacks()
        expect(status==noErr && screenshotTriggers==1 && recordingTriggers==0,"Screenshot Carbon event must reach only the screenshot callback")
        status=try send(pressed,2)
        await drainCallbacks()
        expect(status==noErr && screenshotTriggers==1 && recordingTriggers==1,"Recording Carbon event must reach only the recording callback")
        for _ in 0..<4{_ = try send(pressed,2)}
        await drainCallbacks()
        expect(screenshotTriggers==1 && recordingTriggers==1,"A held recording shortcut must not repeatedly toggle capture")
        _ = try send(released,1);_ = try send(pressed,1)
        await drainCallbacks()
        expect(screenshotTriggers==2 && recordingTriggers==1,"Releasing screenshot must only rearm screenshot")
        _ = try send(pressed,2)
        await drainCallbacks()
        expect(recordingTriggers==1,"Screenshot release must not rearm a held recording key")
        _ = try send(released,2);_ = try send(pressed,2)
        await drainCallbacks()
        expect(screenshotTriggers==2 && recordingTriggers==2,"Recording release must rearm the next independent recording press")
        _ = try send(pressed,99);_ = try send(pressed,1,signature:0x54455354)
        await drainCallbacks()
        expect(screenshotTriggers==2 && recordingTriggers==2,"Unknown shortcut IDs and signatures must not invoke either callback")
        screenshot.unregister();recording.unregister()
        _ = try send(pressed,1);_ = try send(pressed,2)
        await drainCallbacks()
        expect(screenshotTriggers==3 && recordingTriggers==3,"Unregister must reset both held-key latches")
        _ = try send(released,1);_ = try send(released,2)
        await drainCallbacks()
        expect(screenshotTriggers==3 && recordingTriggers==3,"Release events must never invoke capture")
        withExtendedLifetime((screenshot,recording)){}
        print("PASS Carbon routing: \(checks-destinationChecks) checks; independent callbacks, held-key suppression, release/rearm and unknown events")
        print("PASS quick recording: \(checks) checks; no screen or microphone access, no registered global shortcuts, isolated preferences and temporary files")
    }
}
