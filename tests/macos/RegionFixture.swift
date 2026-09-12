import AppKit
final class Pattern:NSView{
 override func draw(_ rect:NSRect){
  let w=bounds.width/2,h=bounds.height/2
  for (color,r) in [(NSColor(srgbRed:1,green:0,blue:0,alpha:1),CGRect(x:0,y:h,width:w,height:h)),(NSColor(srgbRed:0,green:1,blue:0,alpha:1),CGRect(x:w,y:h,width:w,height:h)),(NSColor(srgbRed:0,green:0,blue:1,alpha:1),CGRect(x:0,y:0,width:w,height:h)),(NSColor(srgbRed:1,green:1,blue:0,alpha:1),CGRect(x:w,y:0,width:w,height:h))]{color.setFill();r.fill()}
 }
}
let app=NSApplication.shared;app.setActivationPolicy(.accessory)
let screen=NSScreen.main!,r=CGRect(x:screen.frame.minX+120,y:screen.frame.maxY-400,width:320,height:240)
let window=NSWindow(contentRect:r,styleMask:.borderless,backing:.buffered,defer:false)
window.contentView=Pattern(frame:.init(origin:.zero,size:r.size));window.title="Snapliq Region Test Pattern"
window.level = .floating;window.makeKeyAndOrderFront(nil)
let id=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
let info:[String:Any]=["displayID":id,"x":r.minX,"y":r.minY,"width":r.width,"height":r.height]
try JSONSerialization.data(withJSONObject:info).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
app.run()
