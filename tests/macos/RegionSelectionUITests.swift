import AppKit
@main struct RegionSelectionUITests {
 @MainActor static func main(){
  let app=NSApplication.shared;app.setActivationPolicy(.accessory)
  let screen=NSScreen.main!,frame=screen.frame,scale=screen.backingScaleFactor
  let b=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(frame.width*scale),pixelsHigh:Int(frame.height*scale),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
  let id=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
  let snapshot=DisplaySnapshot(id:id,frame:frame,image:b.cgImage!,capturedAt:now())
  func descendants(_ view:NSView)->[NSView]{[view]+view.subviews.flatMap{descendants($0)}}
  func event(_ code:UInt16)->NSEvent{NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:now(),windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code)!}
  let session=SelectionSession(snapshots:[snapshot],started:now(),mode:.region,candidates:[],recordingSelection:true)
  let clipboardCount=NSPasteboard.general.changeCount
  var chosen:RecordingRegion?,finished=0
  session.onRecord={chosen=$0};session.onFinish={_ in finished+=1}
  DispatchQueue.main.async{
   session.present();session.down(at:.init(x:frame.minX+100,y:frame.minY+100));session.drag(to:.init(x:frame.minX+320,y:frame.minY+270));session.up(at:.init(x:frame.minX+320,y:frame.minY+270))
   let buttons=NSApp.windows.filter(\.isVisible).compactMap(\.contentView).flatMap{descendants($0)}.compactMap{$0 as? NSButton}
   precondition(Set(buttons.map(\.title))==["取消","使用此区域 ↵"],"Region mode must not expose screenshot export actions")
   for button in buttons {
    let root=button.window!.contentView!;root.layoutSubtreeIfNeeded()
    precondition(root.bounds.insetBy(dx:-0.5,dy:-0.5).contains(button.convert(button.bounds,to:root)))
   }
   session.key(event(36))
   precondition(chosen?.pixelWidth==Int(220*scale) && chosen?.pixelHeight==Int(170*scale))
   precondition(finished==1 && NSPasteboard.general.changeCount==clipboardCount)
   precondition(!NSApp.windows.contains(where:{$0.isVisible}))
   let cancel=SelectionSession(snapshots:[snapshot],started:now(),mode:.region,candidates:[],recordingSelection:true)
   cancel.onRecord={_ in fatalError("Escape must not select a recording source")}
   cancel.present();cancel.key(event(53))
   precondition(!NSApp.windows.contains(where:{$0.isVisible}))
   print("PASS native region selection: region-only buttons fit, Enter returns exact crop without clipboard mutation, Escape removes overlays")
   NSApp.terminate(nil)
  }
  app.run()
 }
}
