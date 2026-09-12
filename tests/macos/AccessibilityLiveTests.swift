import AppKit
import ApplicationServices
@main struct AccessibilityLiveTests {
 @MainActor static func main() async throws {
  _ = NSApplication.shared
  guard AXIsProcessTrusted() else{print("BLOCKED: test host needs Accessibility permission");exit(3)}
  let meta=URL(fileURLWithPath:CommandLine.arguments[1]),fixture=Process()
  fixture.executableURL=URL(fileURLWithPath:CommandLine.arguments[2]);fixture.arguments=[meta.path]
  try? FileManager.default.removeItem(at:meta);try fixture.run()
  defer{if fixture.isRunning{fixture.terminate()}}
  for _ in 0..<100{if FileManager.default.fileExists(atPath:meta.path){break};try await Task.sleep(nanoseconds:20_000_000)}
  let data=try JSONSerialization.jsonObject(with:Data(contentsOf:meta)) as! [String:Any]
  func rect(_ name:String)->CGRect{let r=data[name] as! [Double];return CGRect(x:r[0],y:r[1],width:r[2],height:r[3])}
  let bounds=rect("window"),button=rect("button"),point=CGPoint(x:button.midX,y:button.midY)
  let top=NSScreen.screens.first!.frame.maxY
  let original=NSEvent.mouseLocation
  defer{CGWarpMouseCursorPosition(.init(x:original.x,y:top-original.y))}
  CGWarpMouseCursorPosition(.init(x:point.x,y:top-point.y))
  // A foreground overlay owned by this test must not become the AX target.
  let overlay=NSPanel(contentRect:bounds,styleMask:.borderless,backing:.buffered,defer:false)
  overlay.isOpaque=false;overlay.backgroundColor=NSColor.black.withAlphaComponent(0.1);overlay.level = .statusBar
  overlay.orderFrontRegardless();defer{overlay.orderOut(nil)}
  let selector=SmartSelection(targets:[DesktopWindowTarget(frame:bounds,pid:fixture.processIdentifier)],controlsEnabled:{true})
  var found:CGRect?
  selector.hit(point){found=$0}
  for _ in 0..<100{if let f=found,f.width<bounds.width{break};try await Task.sleep(nanoseconds:20_000_000)}
  selector.cancel()
  guard let f=found,f.contains(point),f.width<bounds.width/2,f.height<bounds.height/2 else{print("FAIL no internal control resolved:",String(describing:found));exit(2)}
  print("PASS real native AX control behind own overlay:",f,"window:",bounds)
 }
}
