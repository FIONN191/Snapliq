import AppKit
import ScreenCaptureKit
import AVFoundation
@main struct LiveRecordingTests {
 @MainActor static func main() async throws {
  _ = NSApplication.shared
  guard CGPreflightScreenCaptureAccess() else {print("BLOCKED: test process does not have screen recording permission");exit(3)}
  let destination=URL(fileURLWithPath:CommandLine.arguments[1])
  try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
  let content=try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
  guard let display=content.displays.first else{throw CaptureFailure.message("No display")}
  let filter=SCContentFilter(display:display,excludingApplications:content.applications.filter{$0.processID==getpid()},exceptingWindows:[])
  let recorder=RecordingController()
  let ui=RecordingUI(controller:recorder)
  recorder.onStateChanged={state in ui.update(state)}
  let system=CommandLine.arguments.contains("--system-audio")
  let out=destination.appendingPathComponent(system ? "live-system-audio.mp4":"live-desktop.mp4")
  try? FileManager.default.removeItem(at:out)
  var complete=false,failure:String?
  recorder.onFinished={url,error in complete=true;failure=error;print("FINISHED",url?.path ?? "none",error ?? "ok")}
  print("START real ScreenCaptureKit",display.width,display.height,"Chrome dependency: none")
  try await recorder.start(filter:filter,windowID:nil,width:Int(filter.contentRect.width*CGFloat(filter.pointPixelScale)),height:Int(filter.contentRect.height*CGFloat(filter.pointPixelScale)),url:out,systemAudio:system,microphone:false)
  try await Task.sleep(nanoseconds:2_000_000_000)
  recorder.togglePause()
  try await Task.sleep(nanoseconds:1_000_000_000)
  recorder.togglePause()
  try await Task.sleep(nanoseconds:2_000_000_000)
  recorder.stop()
  for _ in 0..<300 {if complete{break};try await Task.sleep(nanoseconds:100_000_000)}
  precondition(complete && failure==nil,failure ?? "Finalize timed out")
  let asset=AVURLAsset(url:out),seconds=try await AVURLAsset(url:out).load(.duration).seconds
  precondition(abs(seconds-4)<0.4,"Incorrect live paused duration: \(seconds)")
  let audio=try await asset.loadTracks(withMediaType:.audio)
  if system {precondition(!audio.isEmpty,"System audio track absent")}
  print("PASS live capture with native control panel and pause: seconds=\(seconds), audioTracks=\(audio.count)")
 }
}
