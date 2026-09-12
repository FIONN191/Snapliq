import AppKit
@main struct ImagePipelineTests {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  func solid(_ width:Int,_ height:Int,_ color:CGColor)->CGImage{
   let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
   c.setFillColor(color);c.fill(CGRect(x:0,y:0,width:width,height:height));return c.makeImage()!
  }
  let red=solid(200,100,NSColor.red.cgColor),blue=solid(100,50,NSColor.blue.cgColor)
  let screens=[DisplaySnapshot(id:1,frame:CGRect(x:-100,y:0,width:100,height:50),image:red,capturedAt:0),DisplaySnapshot(id:2,frame:CGRect(x:0,y:0,width:100,height:50),image:blue,capturedAt:0)]
  let single=try CaptureBackend.crop(CGRect(x:-80,y:10,width:30,height:25),from:screens)
  precondition(single.width==60 && single.height==50)
  let mixed=try CaptureBackend.crop(CGRect(x:-25,y:0,width:50,height:50),from:screens)
  precondition(mixed.width==100 && mixed.height==100)
  let rep=NSBitmapImageRep(cgImage:mixed)
  precondition(rep.colorAt(x:10,y:50)!.redComponent>0.99 && rep.colorAt(x:90,y:50)!.blueComponent>0.99)
  let names=try (0..<10).map{_ in try CaptureBackend.save(mixed,to:root)}
  precondition(Set(names).count==10)
  for url in names{let saved=NSBitmapImageRep(data:try Data(contentsOf:url))!;precondition(saved.pixelsWide==100 && saved.pixelsHigh==100)}
  let leftovers=try FileManager.default.contentsOfDirectory(atPath:root.path).filter{$0.hasPrefix(".snapliq-")};precondition(leftovers.isEmpty)
  let blocked=root.appendingPathComponent("read-only",isDirectory:true);try FileManager.default.createDirectory(at:blocked,withIntermediateDirectories:true)
  try FileManager.default.setAttributes([.posixPermissions:0o500],ofItemAtPath:blocked.path)
  defer{try? FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:blocked.path)}
  do{_ = try CaptureBackend.save(mixed,to:blocked);fatalError("Expected save permission error")}catch{print("PASS: permission failure propagated")}
  print("PASS: native pixel crop, negative origin, mixed density composition, PNG roundtrip, 10 collision-safe saves, temporary cleanup")
 }
}
