import AppKit
import ApplicationServices
let args=CommandLine.arguments
if args.count==1{print("trusted=\(AXIsProcessTrusted())");exit(0)}
guard AXIsProcessTrusted() else{print("Input permission unavailable");exit(2)}
func mouse(_ type:CGEventType,_ x:Double,_ y:Double){CGEvent(mouseEventSource:nil,mouseType:type,mouseCursorPosition:CGPoint(x:x,y:y),mouseButton:.left)?.post(tap:.cghidEventTap)}
if args[1]=="drag" {
 let x=Double(args[2])!,y=Double(args[3])!,xx=Double(args[4])!,yy=Double(args[5])!
 mouse(.mouseMoved,x,y);mouse(.leftMouseDown,x,y)
 for i in 1...12{let f=Double(i)/12;mouse(.leftMouseDragged,x+(xx-x)*f,y+(yy-y)*f);Thread.sleep(forTimeInterval:0.008)}
 mouse(.leftMouseUp,xx,yy)
} else if args[1]=="key" {
 let code=CGKeyCode(args[2])!
 for down in [true,false]{let event=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:down);if args.count>3{event?.flags = .maskCommand};event?.post(tap:.cghidEventTap);Thread.sleep(forTimeInterval:0.03)}
} else if args[1]=="click"{
 let x=Double(args[2])!,y=Double(args[3])!;mouse(.mouseMoved,x,y);mouse(.leftMouseDown,x,y);mouse(.leftMouseUp,x,y)
}

Thread.sleep(forTimeInterval:0.15)
