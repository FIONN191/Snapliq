import AppKit
import ScreenCaptureKit
import AVFoundation
@main struct WindowClosureTests {
 @MainActor static func main() async throws {
  _ = NSApplication.shared
  guard CGPreflightScreenCaptureAccess() else{print("BLOCKED: test process screen recording permission unavailable");exit(3)}
  let output=URL(fileURLWithPath:CommandLine.arguments[1])
  let fixture=Process();fixture.executableURL=URL(fileURLWithPath:CommandLine.arguments[2]);try fixture.run()
  defer{if fixture.isRunning{fixture.terminate()}}
  try await Task.sleep(nanoseconds:700_000_000)
  let content=try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
  guard let window=content.windows.first(where:{$0.owningApplication?.processID==fixture.processIdentifier && $0.frame.width>100}) else{throw CaptureFailure.message("Fixture window unavailable")}
  let filter=SCContentFilter(desktopIndependentWindow:window)
  let recorder=RecordingController()
  var completed=false,saved:URL?,reason:String?
  recorder.onFinished={url,error in saved=url;reason=error;completed=true}
  try await recorder.start(filter:filter,windowID:window.windowID,width:Int(filter.contentRect.width*CGFloat(filter.pointPixelScale)),height:Int(filter.contentRect.height*CGFloat(filter.pointPixelScale)),url:output,systemAudio:false,microphone:false)
  try await Task.sleep(nanoseconds:3_000_000_000)
  fixture.terminate()
  for _ in 0..<150 {if completed{break};try await Task.sleep(nanoseconds:100_000_000)}
  guard completed,saved != nil,recorder.state == .idle else{
   recorder.stop();print("FAIL source close did not finalize:",reason ?? "no callback");exit(2)
  }
  let asset=AVURLAsset(url:output),seconds=try await AVURLAsset(url:output).load(.duration).seconds
  let tracks=try await asset.loadTracks(withMediaType:.video)
  guard seconds>1 && seconds<10 && !tracks.isEmpty else{print("FAIL invalid saved video:",seconds);exit(2)}
  print("PASS real WIndow source close: finalized MP4; controller idle; seconds=\(seconds); reason=\(reason ?? "none")")
 }
}
