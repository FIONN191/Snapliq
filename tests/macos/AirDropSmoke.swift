import AppKit
@main struct AirDropSmoke {
 static func main(){
  let app=NSApplication.shared;app.setActivationPolicy(.accessory)
  let context=CGContext(data:nil,width:256,height:128,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.setFillColor(NSColor.white.cgColor);context.fill(.init(x:0,y:0,width:256,height:128))
  let before=Set((try? FileManager.default.contentsOfDirectory(at:AirDropTransfer.temporaryDirectory,includingPropertiesForKeys:nil)) ?? [])
  let transfer=AirDropTransfer()
  DispatchQueue.main.async{
   transfer.share(context.makeImage()!){error in
    print("AirDrop completion:",error ?? "cancelled_or_finished")
    let remaining=(try? FileManager.default.contentsOfDirectory(at:AirDropTransfer.temporaryDirectory,includingPropertiesForKeys:nil)) ?? []
    precondition(Set(remaining).subtracting(before).isEmpty,"Share temporary file not removed")
    print("PASS system AirDrop Cancel callback and temporary-file cleanup")
    app.terminate(nil)
   }
  }
  DispatchQueue.main.asyncAfter(deadline:.now()+55){print("AirDrop chooser timeout; smoke test was not completed");app.terminate(nil)}
  withExtendedLifetime(transfer){app.run()}
 }
}
