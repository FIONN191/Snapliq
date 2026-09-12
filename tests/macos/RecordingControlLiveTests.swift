import AppKit
import ScreenCaptureKit
import AVFoundation
@main struct RecordingControlLiveTests {
 static func main(){
  let app=NSApplication.shared;app.setActivationPolicy(.accessory)
  DispatchQueue.main.async{Task{do{try await run()}catch{print("FAIL",error);exit(2)};NSApp.terminate(nil)}}
  app.run()
 }
 @MainActor static func run() async throws {
  guard CGPreflightScreenCaptureAccess() else{print("BLOCKED screen recording permission");exit(3)}
  let folder=URL(fileURLWithPath:CommandLine.arguments[1])
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  let fixture=Process();fixture.executableURL=URL(fileURLWithPath:CommandLine.arguments[2]);fixture.arguments=[folder.appendingPathComponent("fixture.json").path]
  try fixture.run();defer{if fixture.isRunning{fixture.terminate()}}
  try await Task.sleep(nanoseconds:700_000_000)
  let content=try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
  guard let window=content.windows.first(where:{$0.owningApplication?.processID==fixture.processIdentifier && $0.frame.width>100}) else{throw CaptureFailure.message("Fixture window unavailable")}
  let filter=SCContentFilter(desktopIndependentWindow:window),recorder=RecordingController(),ui=RecordingUI(controller:recorder)
  var states=[String](),completed=false,saved:URL?,failure:String?
  recorder.onStateChanged={state in states.append(state.rawValue);ui.update(state)}
  recorder.onFinished={url,error in saved=url;failure=error;completed=true}
  try await recorder.start(filter:filter,windowID:window.windowID,width:Int(filter.contentRect.width*CGFloat(filter.pointPixelScale)),height:Int(filter.contentRect.height*CGFloat(filter.pointPixelScale)),url:folder.appendingPathComponent("controls.mp4"),systemAudio:false,microphone:false)
  try String(getpid()).write(to:folder.appendingPathComponent("ready.pid"),atomically:true,encoding:.utf8)
  for _ in 0..<300{if completed{break};try await Task.sleep(nanoseconds:100_000_000)}
  guard completed,let saved=saved,failure==nil else{recorder.stop();print("FAIL controls did not finish:",failure ?? "timeout");exit(2)}
  let expected=["preparing","recording","paused","recording","finishing","idle"]
  precondition(states==expected,"Unexpected state sequence: \(states)")
  let seconds=try await AVURLAsset(url:saved).load(.duration).seconds
  print("PASS real AX pause, resume and stop actions; exact states:",states,"seconds:",seconds)
 }
}
