import AppKit
@main struct SelectionUITests {
 @MainActor static func main(){
  let app=NSApplication.shared;app.setActivationPolicy(.accessory)
  let screen=NSScreen.main!,frame=screen.frame,scale=screen.backingScaleFactor
  let size=NSSize(width:frame.width*scale,height:frame.height*scale)
  let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width),pixelsHigh:Int(size.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
  NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
  NSColor.white.setFill();NSRect(origin:.zero,size:size).fill()
  ("Snapliq Capture 123" as NSString).draw(at:.init(x:200,y:size.height-400),withAttributes:[.font:NSFont.systemFont(ofSize:68),.foregroundColor:NSColor.black])
  ("截图与录屏工具" as NSString).draw(at:.init(x:200,y:size.height-520),withAttributes:[.font:NSFont.systemFont(ofSize:68),.foregroundColor:NSColor.black])
  NSGraphicsContext.restoreGraphicsState()
  let ocr=OCRController()
  var active:SelectionSession?,finished=0
  func descendants(_ root:NSView)->[NSView]{[root]+root.subviews.flatMap{descendants($0)}}
  func buttons(_ windows:[NSWindow])->[NSButton]{windows.compactMap(\.contentView).flatMap{descendants($0)}.compactMap{$0 as? NSButton}}
  func require(_ condition:Bool,_ message:String)throws{
   if !condition{throw NSError(domain:"SelectionUITests",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
  }
  func start(){
   let session=SelectionSession(snapshots:[DisplaySnapshot(id:1,frame:frame,image:bitmap.cgImage!,capturedAt:now())],started:now(),mode:.screen,candidates:[])
   session.onFinish={_ in finished+=1;active=nil}
   session.onExtractText={image in ocr.present(image)}
   active=session;session.present()
  }
  let clipboard=NSPasteboard.general
  let saved=clipboard.pasteboardItems?.map{item in item.types.compactMap{type -> (NSPasteboard.PasteboardType,Data)? in guard let data=item.data(forType:type) else{return nil};return(type,data)}} ?? []
  func restoreClipboard(){
   clipboard.clearContents()
   let items=saved.map{pairs -> NSPasteboardItem in let item=NSPasteboardItem();pairs.forEach{item.setData($0.1,forType:$0.0)};return item}
   if !items.isEmpty{clipboard.writeObjects(items)}
  }
  DispatchQueue.main.async{
   Task { @MainActor in
    var status:Int32=0
    do {
     start()
     weak var firstSession=active
     try await Task.sleep(nanoseconds:300_000_000)
     let toolbarButtons=buttons(NSApp.windows.filter(\.isVisible))
     // performClick also works for clipped buttons; check visible geometry first.
     for control in toolbarButtons where ["提取文字","复制","AirDrop","下载 ▾","取消","完成 ↵"].contains(control.title) {
      guard let root=control.window?.contentView else{throw NSError(domain:"SelectionUITests",code:2)}
      root.layoutSubtreeIfNeeded()
      let bounds=control.convert(control.bounds,to:root)
      try require(bounds.width+0.5>=control.intrinsicContentSize.width && root.bounds.insetBy(dx:-0.5,dy:-0.5).contains(bounds),"Clipped toolbar action: "+control.title)
     }
     guard let extract=toolbarButtons.first(where:{$0.title=="提取文字"}) else{throw NSError(domain:"SelectionUITests",code:3)}
     extract.performClick(nil)
     try require(active==nil && finished==1,"OCR must end the capture session immediately")
     // AppKit may retain an action target until this event's autorelease pool drains.
     try await Task.sleep(nanoseconds:100_000_000)
     try require(firstSession==nil,"OCR must release the old session and its display snapshots")
     try require(!NSApp.windows.contains{$0 is SelectionWindow && $0.isVisible},"Capture overlay remains after OCR handoff")
     try require(!buttons(NSApp.windows.filter(\.isVisible)).contains{["截图","屏幕录制","完成 ↵"].contains($0.title)},"Capture toolbars remain after OCR handoff")
     var panel:NSWindow?,text:NSTextView?
     for _ in 0..<100 {
      panel=NSApp.windows.first{$0.isVisible && $0.title.hasPrefix("提取文字")}
      text=panel?.contentView.flatMap{descendants($0).compactMap{$0 as? NSTextView}.first}
      if text?.string.contains("Snapliq")==true && text?.string.contains("截图")==true{break}
      try await Task.sleep(nanoseconds:100_000_000)
     }
     guard let panel=panel,let text=text else{throw NSError(domain:"SelectionUITests",code:4)}
     try require(text.string.contains("Snapliq") && text.string.contains("截图"),"Chinese/English OCR did not complete after session release")
     text.string+="\nEdited locally"
     buttons([panel]).first{$0.title=="复制文本"}!.performClick(nil)
     try require(clipboard.string(forType:.string)?.contains("Edited locally")==true,"Editable OCR text copy failed")

     // An open result must not block a fresh capture or disappear when it finishes.
     start()
     try require(NSApp.windows.contains{$0 is SelectionWindow && $0.isVisible},"New capture did not become selectable")
     buttons(NSApp.windows.filter(\.isVisible)).first{$0.title=="复制"}!.performClick(nil)
     let png=clipboard.data(forType:.png).flatMap{NSBitmapImageRep(data:$0)}
     try require(png?.pixelsWide==Int(size.width) && png?.pixelsHigh==Int(size.height),"New capture failed to copy actual image data")
     try require(active==nil && finished==2 && panel.isVisible,"New capture changed OCR lifetime")
     panel.performClose(nil)
     try await Task.sleep(nanoseconds:200_000_000)
     try require(active==nil && finished==2,"Closing OCR re-entered or re-finished capture")
     try require(!NSApp.windows.contains{$0 is SelectionWindow && $0.isVisible},"Closing OCR restored old overlay")
     try require(!buttons(NSApp.windows.filter(\.isVisible)).contains{$0.title=="提取文字"},"Closing OCR restored old toolbar")

     // Closing a result before recognition completes must not resurrect any UI.
     start()
     buttons(NSApp.windows.filter(\.isVisible)).first{$0.title=="提取文字"}!.performClick(nil)
     NSApp.windows.first{$0.isVisible && $0.title.hasPrefix("提取文字")}!.performClose(nil)
     try await Task.sleep(nanoseconds:500_000_000)
     try require(active==nil && finished==3,"Early OCR close left a capture session active")
     try require(!NSApp.windows.contains{$0.isVisible && ($0 is SelectionWindow || $0.title.hasPrefix("提取文字"))},"Late OCR completion reopened UI")
     print("PASS native selection UI: OCR ends and releases capture; editable Chinese/English text; next capture and image copy; closing OCR never restores overlays; early close; toolbar layout")
    }catch{fputs("FAIL selection UI: \(error.localizedDescription)\n",stderr);status=1}
    active?.cancel()
    for window in NSApp.windows where window.title.hasPrefix("提取文字"){window.close()}
    restoreClipboard()
    exit(status)
   }
  }
  app.run()
 }
}
