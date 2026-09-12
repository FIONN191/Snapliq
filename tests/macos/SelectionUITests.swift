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
  let session=SelectionSession(snapshots:[DisplaySnapshot(id:1,frame:frame,image:bitmap.cgImage!,capturedAt:now())],started:now(),mode:.screen,candidates:[])
  func descendants(_ root:NSView)->[NSView]{[root]+root.subviews.flatMap{descendants($0)}}
  let clipboard=NSPasteboard.general
  let saved=clipboard.pasteboardItems?.map{item in item.types.compactMap{type -> (NSPasteboard.PasteboardType,Data)? in guard let data=item.data(forType:type) else{return nil};return(type,data)}} ?? []
  session.onFinish={_ in
   let png=clipboard.data(forType:.png).flatMap{NSBitmapImageRep(data:$0)}
   precondition(png?.pixelsWide==Int(size.width)&&png?.pixelsHigh==Int(size.height),"Image clipboard data missing")
   clipboard.clearContents()
   let items=saved.map{pairs -> NSPasteboardItem in let item=NSPasteboardItem();pairs.forEach{item.setData($0.1,forType:$0.0)};return item}
   if !items.isEmpty{clipboard.writeObjects(items)}
   print("PASS actual selection UI: editable OCR, text copy, close restores selection, image copy, toolbar actions")
   NSApp.terminate(nil)
  }
  DispatchQueue.main.async{
   session.present()
   Task { @MainActor in
    try? await Task.sleep(nanoseconds:500_000_000)
    let buttons=NSApp.windows.compactMap(\.contentView).flatMap{descendants($0)}.compactMap{$0 as? NSButton}

    // Programmatic performClick succeeds even for clipped buttons. Verify visible geometry first.
    for control in buttons where ["提取文字","复制","AirDrop","下载 ▾","取消","完成 ↵"].contains(control.title) {
     guard let root=control.window?.contentView else{fatalError("Toolbar window missing")}
     root.layoutSubtreeIfNeeded()
     let frame=control.convert(control.bounds,to:root)
     print("Toolbar geometry:",control.title,"width:",frame.width,"intrinsic:",control.intrinsicContentSize.width,"panel:",root.bounds.width)
     if frame.width + 0.5 < control.intrinsicContentSize.width || !root.bounds.insetBy(dx:-0.5,dy:-0.5).contains(frame) {
      print("FAIL clipped toolbar action:",control.title,"button:",frame,"window:",root.bounds)
      exit(2)
     }
    }
    print("PASS toolbar actions fit within the actual native window")
    guard let extract=buttons.first(where:{$0.title=="提取文字"}) else{fatalError("OCR action absent")}
    extract.performClick(nil)
    var panel:NSWindow?,text:NSTextView?
    for _ in 0..<100 {
     panel=NSApp.windows.first{$0.title.hasPrefix("提取文字")}
     text=panel?.contentView.flatMap{descendants($0).compactMap{$0 as? NSTextView}.first}
     if text?.string.contains("Snapliq")==true{break}
     try? await Task.sleep(nanoseconds:100_000_000)
    }
    guard let panel=panel,let text=text,text.string.contains("截图") else{fatalError("OCR UI did not complete")}
    text.string+="\nEdited locally"
    let copy=descendants(panel.contentView!).compactMap{$0 as? NSButton}.first{$0.title=="复制文本"}!
    copy.performClick(nil);precondition(clipboard.string(forType:.string)?.contains("Edited locally")==true)
    panel.performClose(nil)
    try? await Task.sleep(nanoseconds:200_000_000)
    let restored=NSApp.windows.filter(\.isVisible).compactMap(\.contentView).flatMap{descendants($0)}.compactMap{$0 as? NSButton}.first{$0.title=="复制"}
    precondition(restored != nil,"Selection toolbar not restored")
    restored!.performClick(nil)
   }
  }
  app.run()
 }
}
