import AppKit
import Carbon
import ScreenCaptureKit
import ServiceManagement

enum Product {
    static let info = Bundle.main.infoDictionary ?? [:]
    static let name = info["CFBundleDisplayName"] as? String ?? "Snapliq"
    static let dataDirectory = info["SnapliqDataDirectory"] as? String ?? "Snapliq Development"
    static let version = info["CFBundleShortVersionString"] as? String ?? "development"
    static let tagline = info["SnapliqTagline"] as? String ?? "Capture. Record. Share."
}
extension CGRect {
    var sl: SLRect { SLRect(x: minX,y: minY,width: width,height: height) }
    init(_ r: SLRect) { self.init(x:r.x,y:r.y,width:r.width,height:r.height) }
}
extension CGPoint { var sl: SLPoint { SLPoint(x:x,y:y) } }
func now() -> Double { ProcessInfo.processInfo.systemUptime }
func showError(_ message: String) {
    NSApp.activate(ignoringOtherApps:true)
    let a=NSAlert(); a.messageText=Product.name; a.informativeText=message
    a.alertStyle = .warning; a.addButton(withTitle:"好"); a.runModal()
}
final class Preferences {
    static let shared=Preferences()
    let defaults=UserDefaults.standard
    var shortcutEnabled: Bool { get {defaults.bool(forKey:"shortcutEnabled")} set{defaults.set(newValue,forKey:"shortcutEnabled")} }
    var shortcutKey: UInt32 { get { defaults.object(forKey:"shortcutKey") == nil ? 7 : UInt32(defaults.integer(forKey:"shortcutKey")) } set{defaults.set(Int(newValue),forKey:"shortcutKey")} }
    var shortcutMods: UInt32 { get {defaults.object(forKey:"shortcutMods") == nil ? UInt32(cmdKey) : UInt32(defaults.integer(forKey:"shortcutMods"))} set{defaults.set(Int(newValue),forKey:"shortcutMods")} }
    var shortcutLabel: String { get{defaults.string(forKey:"shortcutLabel") ?? "⌘ X"} set{defaults.set(newValue,forKey:"shortcutLabel")} }
    var orbHidden: Bool {get{defaults.bool(forKey:"orbHidden")} set{defaults.set(newValue,forKey:"orbHidden")} }
    var dateKey: String {
        let parts=Calendar.current.dateComponents([.era,.year,.month,.day],from:Date())
        return "\(parts.era ?? 0)-\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
    var orbDisabledToday: Bool {defaults.string(forKey:"orbDisabledDate")==dateKey}
    func disableToday(){defaults.set(dateKey,forKey:"orbDisabledDate")}
    func restoreOrb(){orbHidden=false;defaults.removeObject(forKey:"orbDisabledDate")}
    func validateDate(){if !orbDisabledToday {defaults.removeObject(forKey:"orbDisabledDate")}}
    var folderURL: URL? {
        guard let data=defaults.data(forKey:"folderBookmark") else{return nil}
        var stale=false
        guard let u=try? URL(resolvingBookmarkData:data,options:.withoutUI,relativeTo:nil,bookmarkDataIsStale:&stale),!stale else{return nil}
        return u
    }
    func setFolder(_ url:URL) throws {
        let data=try url.bookmarkData(options:[],includingResourceValuesForKeys:nil,relativeTo:nil)
        defaults.set(data,forKey:"folderBookmark")
    }
}
final class Metrics {
    static let shared=Metrics()
    let directory: URL
    init() {
        if let i=CommandLine.arguments.firstIndex(of:"--diagnostics-dir"),CommandLine.arguments.count>i+1 {
            directory=URL(fileURLWithPath:CommandLine.arguments[i+1],isDirectory:true)
        } else {
            directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent(Product.dataDirectory+"/Diagnostics")
        }
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    }
    func write(_ event:String,_ fields:[String:Any]=[:]){
        var d=fields;d["event"]=event;d["uptime"]=now()
        guard let data=try? JSONSerialization.data(withJSONObject:d,options:.sortedKeys) else{return}
        let url=directory.appendingPathComponent("events.jsonl")
        if !FileManager.default.fileExists(atPath:url.path){FileManager.default.createFile(atPath:url.path,contents:nil)}
        if let h=try? FileHandle(forWritingTo:url){defer{try? h.close()}; do{try h.seekToEnd();try h.write(contentsOf:data+Data([10]))}catch{}}
    }
}

final class HotkeyService {
    private var key:EventHotKeyRef?
    private var handler:EventHandlerRef?
    var onTrigger:(()->Void)?
    init(){
        var spec=EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(),{ _,_,context in
            guard let context=context else{return OSStatus(eventNotHandledErr)}
            let service=Unmanaged<HotkeyService>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {service.onTrigger?()}
            return noErr
        },1,&spec,Unmanaged.passUnretained(self).toOpaque(),&handler)
    }
    @discardableResult func register() -> OSStatus {
        unregister()
        let p=Preferences.shared
        guard p.shortcutEnabled else{return noErr}
        let id=EventHotKeyID(signature:0x534e4150,id:1)
        let result=RegisterEventHotKey(p.shortcutKey,p.shortcutMods,id,GetApplicationEventTarget(),OptionBits(kEventHotKeyExclusive),&key)
        Metrics.shared.write("hotkey_registration",["status":result,"enabled":result==0])
        return result
    }
    func unregister(){if let key=key{UnregisterEventHotKey(key)};key=nil}
    deinit{unregister();if let handler=handler{RemoveEventHandler(handler)}}
}
final class BrandView:NSView {
    var color:NSColor = .labelColor
    override func draw(_ dirtyRect:NSRect){
        let factor=min(bounds.width,bounds.height)/64
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.translateBy(x:bounds.midX-32*factor,y:bounds.midY-32*factor)
        NSGraphicsContext.current?.cgContext.scaleBy(x:factor,y:factor)
        color.setStroke();color.setFill()
        let p=NSBezierPath();p.lineWidth=6.5;p.lineCapStyle = .round;p.lineJoinStyle = .round
        p.move(to:NSPoint(x:14,y:30));p.line(to:NSPoint(x:14,y:50));p.line(to:NSPoint(x:34,y:50))
        p.move(to:NSPoint(x:30,y:14));p.line(to:NSPoint(x:50,y:14));p.line(to:NSPoint(x:50,y:34));p.stroke()
        NSBezierPath(ovalIn:NSRect(x:28.4,y:28.4,width:7.2,height:7.2)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
func brandImage(size:CGFloat=18)->NSImage {
    let image=NSImage(size:NSSize(width:size,height:size),flipped:false){r in
        let f=size/16
        let p=NSBezierPath();p.lineWidth=1.85*f;p.lineCapStyle = .round;p.lineJoinStyle = .round
        NSColor.black.setStroke();NSColor.black.setFill()
        p.move(to:.init(x:3.5*f,y:7.5*f));p.line(to:.init(x:3.5*f,y:12.5*f));p.line(to:.init(x:8.5*f,y:12.5*f))
        p.move(to:.init(x:7.5*f,y:3.5*f));p.line(to:.init(x:12.5*f,y:3.5*f));p.line(to:.init(x:12.5*f,y:8.5*f));p.stroke()
        NSBezierPath(ovalIn:.init(x:6.9*f,y:6.9*f,width:2.2*f,height:2.2*f)).fill();return true
    }
    image.isTemplate=true;return image
}
func materialView(radius:CGFloat) -> NSView {MaterialSurface(radius:radius)}
