import AppKit
import ScreenCaptureKit
import AVFoundation
@main struct RegionRecordingLiveTests {
 static func main(){let app=NSApplication.shared;app.setActivationPolicy(.accessory)
  DispatchQueue.main.async{Task{do{try await run()}catch{print("FAIL",error);exit(2)};NSApp.terminate(nil)}};app.run()
 }
 @MainActor static func run()async throws{
  guard CGPreflightScreenCaptureAccess() else{print("BLOCKED screen recording permission");exit(3)}
  let out=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
  let fixture=Process();fixture.executableURL=URL(fileURLWithPath:CommandLine.arguments[2]);fixture.arguments=[out.appendingPathComponent("fixture.json").path]
  try fixture.run();defer{if fixture.isRunning{fixture.terminate()}}
  try await Task.sleep(nanoseconds:600_000_000)
  let data=try JSONSerialization.jsonObject(with:Data(contentsOf:out.appendingPathComponent("fixture.json"))) as! [String:NSNumber]
  let id=data["displayID"]!.uint32Value
  let selection=CGRect(x:data["x"]!.doubleValue+30,y:data["y"]!.doubleValue+50,width:220,height:170)
  // A magenta host overlay covers the crop: a correct native exclusion must reveal the fixture below it.
  let overlay=NSWindow(contentRect:selection,styleMask:.borderless,backing:.buffered,defer:false)
  overlay.backgroundColor = .magenta;overlay.level = .statusBar;overlay.orderFrontRegardless();defer{overlay.orderOut(nil)}
  try await Task.sleep(nanoseconds:200_000_000)
  let content=try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
  let display=content.displays.first{$0.displayID==id}!
  let screen=NSScreen.screens.first{($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value==id}!
  let filter=SCContentFilter(display:display,excludingApplications:content.applications.filter{$0.processID==getpid()},exceptingWindows:[])
  if #available(macOS 14.2,*){filter.includeMenuBar=true}
  let region=try RecordingRegion(selection:selection,displayID:id,displayFrame:screen.frame,scale:CGFloat(filter.pointPixelScale))
  let recorder=RecordingController()
  var states=[String](),finished=false,failure:String?
  recorder.onStateChanged={state in states.append(state.rawValue)}
  recorder.onFinished={_,error in failure=error;finished=true}
  let video=out.appendingPathComponent("region.mp4")
  try await recorder.start(filter:filter,windowID:nil,width:region.pixelWidth,height:region.pixelHeight,url:video,systemAudio:false,microphone:false,region:region)
  try await Task.sleep(nanoseconds:1_200_000_000);recorder.togglePause()
  try await Task.sleep(nanoseconds:400_000_000);recorder.togglePause()
  try await Task.sleep(nanoseconds:1_200_000_000);recorder.stop()
  for _ in 0..<150{if finished{break};try await Task.sleep(nanoseconds:100_000_000)}
  precondition(finished && failure==nil,failure ?? "Finalize timeout")
  precondition(states==["preparing","recording","paused","recording","finishing","idle"])
  let asset=AVURLAsset(url:video),generator=AVAssetImageGenerator(asset:AVURLAsset(url:video))
  let image=try generator.copyCGImage(at:CMTime(seconds:0.7,preferredTimescale:600),actualTime:nil)
  precondition(image.width==region.pixelWidth && image.height==region.pixelHeight)
  let b=NSBitmapImageRep(cgImage:image)
  let edgeX=130.0/220,edgeY=100.0/170
  let probes=[(0.1,0.1,[1.0,0,0]),(0.9,0.1,[0.0,1,0]),(0.1,0.9,[0.0,0,1]),(0.9,0.9,[1.0,1,0]),
              (edgeX-0.02,0.1,[1.0,0,0]),(edgeX+0.02,0.1,[0.0,1,0]),
              (0.1,edgeY-0.02,[1.0,0,0]),(0.1,edgeY+0.02,[0.0,0,1])]
  for (x,y,expected) in probes {
   let c=b.colorAt(x:Int(Double(image.width)*x),y:Int(Double(image.height)*y))!.usingColorSpace(.sRGB)!
   let actual=[Double(c.redComponent),Double(c.greenComponent),Double(c.blueComponent)]
   guard zip(actual,expected).allSatisfy({abs($0-$1)<0.2}) else{throw CaptureFailure.message("Wrong region pixels: \(x),\(y) \(actual)")}
  }
  try b.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent("decoded-region.png"))
  let duration=try await asset.load(.duration).seconds
  precondition(duration>2 && duration<3.2)
  print("PASS native region video: \(image.width)x\(image.height), seconds=\(duration), asymmetric four-quadrant pixels, own overlay excluded, pause/resume/finalization")

 }
}
