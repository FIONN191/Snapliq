import AppKit
import ApplicationServices
guard AXIsProcessTrusted() else{fputs("Accessibility permission unavailable\n",stderr);exit(3)}
let pid=pid_t(CommandLine.arguments[1])!,identifier=CommandLine.arguments[2]
let app=AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app,0.1)
func attribute(_ element:AXUIElement,_ name:String)->CFTypeRef?{var value:CFTypeRef?;return AXUIElementCopyAttributeValue(element,name as CFString,&value) == .success ? value:nil}
func find(_ element:AXUIElement,_ depth:Int=0)->AXUIElement?{
 if attribute(element,kAXIdentifierAttribute) as? String == identifier{return element}
 if depth>=16{return nil}
 let children=attribute(element,depth==0 ? kAXWindowsAttribute:kAXChildrenAttribute) as? [AXUIElement] ?? []
 for child in children.prefix(100){if let found=find(child,depth+1){return found}}
 return nil
}
var control:AXUIElement?
for _ in 0..<50{control=find(app);if control != nil{break};Thread.sleep(forTimeInterval:0.1)}
guard let control=control else{print("Windows:",attribute(app,kAXWindowsAttribute) as Any);print("Children:",attribute(app,kAXChildrenAttribute) as Any);fputs("Named control not found\n",stderr);exit(2)}
let error=AXUIElementPerformAction(control,kAXPressAction as CFString)
guard error == .success else{fputs("AX press failed: \(error.rawValue)\n",stderr);exit(2)}
print("PASS AXPress",identifier)
