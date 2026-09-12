import Foundation
import ApplicationServices
let code=CGKeyCode(CommandLine.arguments[1])!
guard AXIsProcessTrusted() else{fputs("Accessibility permission unavailable\n",stderr);exit(2)}
let command=CommandLine.arguments.count>2
let source=CGEventSource(stateID:.hidSystemState)
func send(_ key:CGKeyCode,_ down:Bool,_ flags:CGEventFlags){let event=CGEvent(keyboardEventSource:source,virtualKey:key,keyDown:down);event?.flags=flags;event?.post(tap:.cghidEventTap)}
if command{send(55,true,.maskCommand);Thread.sleep(forTimeInterval:0.005)}
let pressed=ProcessInfo.processInfo.systemUptime
send(code,true,command ? .maskCommand:[])
Thread.sleep(forTimeInterval:0.02)
send(code,false,command ? .maskCommand:[])
if command{send(55,false,[])}
print(pressed)
