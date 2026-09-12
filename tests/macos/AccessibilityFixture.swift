import AppKit
let app=NSApplication.shared;app.setActivationPolicy(.regular)
let window=NSWindow(contentRect:.init(x:200,y:200,width:640,height:360),styleMask:[.titled,.closable],backing:.buffered,defer:false)
window.title="Snapliq AX Fixture"
let button=NSButton(title:"Capture target",target:nil,action:nil);button.bezelStyle = .rounded;button.frame = .init(x:80,y:160,width:170,height:44)
button.setAccessibilityIdentifier("snapliq.fixture.capture")
window.contentView!.addSubview(button)
let text=NSTextField(labelWithString:"Generated native controls for desktop smart selection");text.frame = .init(x:30,y:290,width:560,height:30);window.contentView!.addSubview(text)
window.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true);window.contentView!.layoutSubtreeIfNeeded()
let bounds=window.convertToScreen(button.convert(button.bounds,to:nil))
let info:[String:Any]=["pid":getpid(),"window":[window.frame.minX,window.frame.minY,window.frame.width,window.frame.height],"button":[bounds.minX,bounds.minY,bounds.width,bounds.height]]
try JSONSerialization.data(withJSONObject:info).write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
app.run()
