import AppKit
final class Surface:NSView{
 override func draw(_ rect:NSRect){
  NSColor(srgbRed:0.16,green:0.45,blue:0.65,alpha:1).setFill();bounds.fill()
  let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:24,weight:.semibold),.foregroundColor:NSColor.white]
  ("Snapliq — native capture verification" as NSString).draw(at:NSPoint(x:100,y:bounds.height-150),withAttributes:attrs)
  ("This is a generated local test surface. No browser is involved." as NSString).draw(at:NSPoint(x:100,y:100),withAttributes:[.font:NSFont.systemFont(ofSize:14),.foregroundColor:NSColor.white])
 }
}
let app=NSApplication.shared;app.setActivationPolicy(.regular)
let window=NSWindow(contentRect:NSScreen.main!.frame,styleMask:.borderless,backing:.buffered,defer:false)
window.title="Snapliq Capture Verification";window.contentView=Surface(frame:NSRect(origin:.zero,size:window.frame.size));window.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true);app.run()
