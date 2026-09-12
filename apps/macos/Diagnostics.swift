import AppKit
import ScreenCaptureKit
@MainActor
func runDiagnostics(app:AppDelegate) async {
    let log=Metrics.shared
    func record(_ name:String,_ pass:Bool){log.write("test",["name":name,"passed":pass])}
    let context=CGContext(data:nil,width:200,height:100,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.red.cgColor);context.fill(.init(x:0,y:0,width:100,height:100))
    context.setFillColor(NSColor.blue.cgColor);context.fill(.init(x:100,y:0,width:100,height:100))
    let snapshot=DisplaySnapshot(id:0,frame:.init(x:-100,y:0,width:100,height:50),image:context.makeImage()!,capturedAt:now())
    do{
        let crop=try CaptureBackend.crop(.init(x:-50,y:0,width:50,height:50),from:[snapshot])
        let pixel=NSBitmapImageRep(cgImage:crop).colorAt(x:25,y:25)?.usingColorSpace(.deviceRGB)
        record("negative_origin_retina_crop_blue",crop.width==100 && crop.height==100 && (pixel?.blueComponent ?? 0)>0.9)
        let temp=log.directory.appendingPathComponent("image-tests",isDirectory:true)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
        let a=try CaptureBackend.save(crop,to:temp),b=try CaptureBackend.save(crop,to:temp)
        record("non_overwriting_save",a != b && FileManager.default.fileExists(atPath:a.path))
        let original=NSPasteboard.general.pasteboardItems?.map{item in item.types.compactMap{t -> (NSPasteboard.PasteboardType,Data)? in guard let d=item.data(forType:t) else{return nil};return (t,d)}} ?? []
        try CaptureBackend.copy(crop)
        let png=NSPasteboard.general.data(forType:.png).flatMap{NSBitmapImageRep(data:$0)}
        record("clipboard_real_png_roundtrip",png?.pixelsWide==100 && png?.pixelsHigh==100)
        NSPasteboard.general.clearContents()
        let restored=original.map{types -> NSPasteboardItem in let item=NSPasteboardItem();for (type,data) in types{item.setData(data,forType:type)};return item}
        if !restored.isEmpty{NSPasteboard.general.writeObjects(restored)}
    }catch{record("image_pipeline",false);log.write("test_error",["error":error.localizedDescription])}
    guard CGPreflightScreenCaptureAccess() else {
        log.write("diagnostics_capture_blocked",["reason":"screen_permission_required","syntheticTestsCompleted":true]);app.settings.present();return
    }
    app.orb.temporarilyHidden=true;app.orb.refresh()
    do{
        let iterations=CommandLine.arguments.contains("--benchmark") ? 100:3
        var times=[Double]()
        for _ in 0..<iterations {
            let t=now();let images=try await app.backend.capture();times.append((now()-t)*1000)
            record("capture_frame_nonempty",images.allSatisfy{$0.image.width>0 && $0.image.height>0})
            log.write("capture_sample",["ms":times.last!,"source":"programmatic_diagnostic_not_hotkey","displays":images.map{["width":$0.image.width,"height":$0.image.height,"logicalWidth":$0.frame.width,"logicalHeight":$0.frame.height]}])
        }
        times.sort()
        log.write("capture_benchmark",["count":times.count,"p50_ms":times[Int(ceil(Double(times.count)*0.5))-1],"p95_ms":times[Int(ceil(Double(times.count)*0.95))-1],"scope":"capture backend only, not physical hotkey or selection latency"])
        app.orb.temporarilyHidden=false;app.orb.refresh();log.write("diagnostics_completed")
    }catch{log.write("diagnostics_capture_failed",["error":error.localizedDescription]);app.orb.temporarilyHidden=false;app.orb.refresh()}
}
