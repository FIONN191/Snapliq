import AppKit
import AVFoundation
@main struct ServiceTests {
 @MainActor static func main() async throws {
  _ = NSApplication.shared
  let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
  let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1100,pixelsHigh:230,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
  NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
  NSColor.white.setFill();NSRect(x:0,y:0,width:1100,height:230).fill()
  ("Snapliq Capture 123" as NSString).draw(at:.init(x:30,y:145),withAttributes:[.font:NSFont.systemFont(ofSize:48),.foregroundColor:NSColor.black])
  ("截图与录屏工具" as NSString).draw(at:.init(x:30,y:50),withAttributes:[.font:NSFont.systemFont(ofSize:48),.foregroundColor:NSColor.black])
  NSGraphicsContext.restoreGraphicsState()
  let text=try await Task.detached{try LocalOCR.recognize(bitmap.cgImage!)}.value
  precondition(text.contains("Snapliq") && text.contains("123") && text.contains("截图"),text)
  print("PASS local Chinese/English OCR:",text.replacingOccurrences(of:"\n",with:" / "))
  let video=directory.appendingPathComponent("pause-timeline.mp4");try? FileManager.default.removeItem(at:video)
  let encoder=try RecordingEncoder(url:video,width:320,height:180,systemAudio:false,microphone:false)
  func frame(_ i:Int)throws->CMSampleBuffer {
   var pixel:CVPixelBuffer?
   precondition(CVPixelBufferCreate(kCFAllocatorDefault,320,180,kCVPixelFormatType_32BGRA,[kCVPixelBufferCGImageCompatibilityKey:true,kCVPixelBufferCGBitmapContextCompatibilityKey:true] as CFDictionary,&pixel)==kCVReturnSuccess)
   let p=pixel!;CVPixelBufferLockBaseAddress(p,[])
   let bytes=CVPixelBufferGetBaseAddress(p)!.assumingMemoryBound(to:UInt8.self),stride=CVPixelBufferGetBytesPerRow(p)
   for y in 0..<180 {for x in 0..<320 {let o=y*stride+x*4;bytes[o]=UInt8(i%255);bytes[o+1]=100;bytes[o+2]=210;bytes[o+3]=255}}
   CVPixelBufferUnlockBaseAddress(p,[])
   var format:CMVideoFormatDescription?;CMVideoFormatDescriptionCreateForImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:p,formatDescriptionOut:&format)
   var timing=CMSampleTimingInfo(duration:CMTime(value:1,timescale:30),presentationTimeStamp:CMTime(value:Int64(i),timescale:30),decodeTimeStamp:.invalid)
   var sample:CMSampleBuffer?;CMSampleBufferCreateReadyWithImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:p,formatDescription:format!,sampleTiming:&timing,sampleBufferOut:&sample)
   return sample!
  }
  for i in 0..<30 {let f=try frame(i);encoder.queue.sync{encoder.consume(f,type:0)};try await Task.sleep(nanoseconds:10_000_000)}
  encoder.setPaused(true,at:CMTime(value:1,timescale:1))
  for i in 30..<90 {let f=try frame(i);encoder.queue.sync{encoder.consume(f,type:0)}}
  encoder.setPaused(false,at:CMTime(value:3,timescale:1))
  for i in 90..<120 {let f=try frame(i);encoder.queue.sync{encoder.consume(f,type:0)};try await Task.sleep(nanoseconds:10_000_000)}
  try await encoder.finish()
  let asset=AVURLAsset(url:video);let seconds=try await asset.load(.duration).seconds
  precondition(abs(seconds-2)<0.12,"Pause gap not removed: \(seconds)")
  precondition(encoder.frameCount>=50,"Unexpected frame drops")
  print("PASS MP4 finalization and pause timeline: seconds=\(seconds), frames=\(encoder.frameCount), dropped=\(encoder.dropped)")
  let stillURL=directory.appendingPathComponent("static-duration.mp4");try? FileManager.default.removeItem(at:stillURL)
  let still=try RecordingEncoder(url:stillURL,width:320,height:180,systemAudio:false,microphone:false)
  let first=try frame(0);still.queue.sync{still.consume(first,type:0)}
  try await still.finish(duration:8)
  let stillDuration=try await AVURLAsset(url:stillURL).load(.duration).seconds
  precondition(abs(stillDuration-8)<0.05,"Static screen shortened: \(stillDuration)")
  print("PASS static screen duration: \(stillDuration) seconds, \(still.frameCount) retained/written frames")
  if CommandLine.arguments.count>2 {
   let source=URL(fileURLWithPath:CommandLine.arguments[2]);let target=directory.appendingPathComponent("mixed.mp4");try? FileManager.default.removeItem(at:target)
   try await RecordingEncoder.mixAudio(from:source,to:target)
   let tracks=try await AVURLAsset(url:target).loadTracks(withMediaType:.audio)
   precondition(tracks.count==1,"Expected one mixed audio track")
   print("PASS dual-audio track export to a single mixed track")
  }
 }
}
