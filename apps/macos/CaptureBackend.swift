import AppKit
import ScreenCaptureKit
import ImageIO

struct DisplaySnapshot {
    let id:CGDirectDisplayID
    let frame:CGRect
    let image:CGImage
    let capturedAt:Double
    var scale:CGFloat{CGFloat(image.width)/frame.width}
}
enum CaptureFailure:LocalizedError {
    case message(String)
    var errorDescription:String?{if case .message(let m)=self{return m};return nil}
}
final class CaptureBackend {
    private var content:SCShareableContent?
    func warmMetadata() async {
        guard CGPreflightScreenCaptureAccess() else{return}
        content=try? await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
    }
    @MainActor
    func capture() async throws -> [DisplaySnapshot] {
        let topology=NSScreen.screens.map { s -> (CGDirectDisplayID,CGRect) in
            ((s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value,s.frame)
        }
        // Refresh enumeration on request; no stream or screen history exists while idle.
        let c=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
        content=c
        let apps=c.applications.filter{$0.processID==ProcessInfo.processInfo.processIdentifier}
        let jobs=topology.map { id,frame in
            Task<DisplaySnapshot,Error> {
                guard let display=c.displays.first(where:{$0.displayID==id}) else{throw CaptureFailure.message("显示器配置已变化，请重新截图。")}
                let filter=SCContentFilter(display:display,excludingApplications:apps,exceptingWindows:[])
                if #available(macOS 14.2,*){filter.includeMenuBar=true}
                let config=SCStreamConfiguration()
                let scale=CGFloat(filter.pointPixelScale)
                config.width=Int((filter.contentRect.width*scale).rounded())
                config.height=Int((filter.contentRect.height*scale).rounded())
                config.showsCursor=false;config.captureResolution = .best
                config.pixelFormat=kCVPixelFormatType_32BGRA
                config.colorSpaceName=CGColorSpace.sRGB
                let image=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
                return DisplaySnapshot(id:id,frame:frame,image:image,capturedAt:now())
            }
        }
        do {
            var images=[DisplaySnapshot]()
            for task in jobs{images.append(try await task.value)}
            let current=NSScreen.screens
            guard current.count==topology.count,zip(current,topology).allSatisfy({$0.0.frame==$0.1.1}) else {
                throw CaptureFailure.message("截图期间显示器配置发生变化，请重试。")
            }
            return images
        } catch {for task in jobs{task.cancel()};throw error}
    }
    static func crop(_ selection:CGRect,from snapshots:[DisplaySnapshot])throws->CGImage{
        let parts=snapshots.filter{$0.frame.intersects(selection)}
        guard !parts.isEmpty,selection.width>=1,selection.height>=1 else{throw CaptureFailure.message("请先选择截图区域。")}
        if parts.count==1 {
            let s=parts[0],r=CGRect(sl_pixels(selection.sl,s.frame.sl,Double(s.image.width),Double(s.image.height)))
            guard let image=s.image.cropping(to:r) else{throw CaptureFailure.message("无法裁剪选区。")}
            return image
        }
        // Different displays may have different source densities. Preserve layout at max density.
        let scale=parts.map(\.scale).max() ?? 1
        let width=Int(ceil(selection.width*scale)),height=Int(ceil(selection.height*scale))
        guard width>0,height>0,width<=32768,height<=32768,Double(width)*Double(height)<=160_000_000 else{throw CaptureFailure.message("跨屏选区过大，请缩小范围。")}
        guard let ctx=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{throw CaptureFailure.message("图像内存不足。")}
        ctx.interpolationQuality = .high
        for s in parts {
            let overlap=selection.intersection(s.frame)
            let pixels=CGRect(sl_pixels(overlap.sl,s.frame.sl,Double(s.image.width),Double(s.image.height)))
            guard let part=s.image.cropping(to:pixels) else{continue}
            // Pixel-aligned source bounds are mapped back to desktop space before clipping.
            let sourceRect=CGRect(x:s.frame.minX+pixels.minX/s.scale,y:s.frame.maxY-pixels.maxY/(CGFloat(s.image.height)/s.frame.height),width:pixels.width/s.scale,height:pixels.height/(CGFloat(s.image.height)/s.frame.height))
            ctx.saveGState()
            ctx.clip(to:CGRect(x:(overlap.minX-selection.minX)*scale,y:(overlap.minY-selection.minY)*scale,width:overlap.width*scale,height:overlap.height*scale))
            ctx.draw(part,in:CGRect(x:(sourceRect.minX-selection.minX)*scale,y:(sourceRect.minY-selection.minY)*scale,width:sourceRect.width*scale,height:sourceRect.height*scale))
            ctx.restoreGState()
        }
        guard let image=ctx.makeImage() else{throw CaptureFailure.message("无法生成截图。")};return image
    }
    static func png(_ image:CGImage)throws->Data{
        let data=NSMutableData()
        guard let dest=CGImageDestinationCreateWithData(data,"public.png" as CFString,1,nil) else{throw CaptureFailure.message("PNG 编码器不可用。")}
        CGImageDestinationAddImage(dest,image,nil)
        guard CGImageDestinationFinalize(dest) else{throw CaptureFailure.message("PNG 编码失败。")}
        return data as Data
    }
    static func copy(_ image:CGImage)throws{
        let data=try png(image)
        let rep=NSBitmapImageRep(cgImage:image)
        let item=NSPasteboardItem();item.setData(data,forType:.png)
        if let tiff=rep.tiffRepresentation{item.setData(tiff,forType:.tiff)}
        let board=NSPasteboard.general;board.clearContents()
        guard board.writeObjects([item]) else{throw CaptureFailure.message("系统剪贴板暂时不可用，请重试。")}
    }
    static func save(_ image:CGImage,to directory:URL)throws->URL {
        let data=try png(image),fm=FileManager.default
        let formatter=DateFormatter();formatter.dateFormat="yyyy-MM-dd_HH-mm-ss"
        let stem="Snapliq_"+formatter.string(from:Date())
        let temp=directory.appendingPathComponent(".snapliq-"+UUID().uuidString+".png")
        try data.write(to:temp,options:.withoutOverwriting)
        defer{try? fm.removeItem(at:temp)}
        for n in 0..<10000{
            let name=stem+(n==0 ? "":"_\(n)")+".png",target=directory.appendingPathComponent(name)
            do{try fm.moveItem(at:temp,to:target);return target}
            catch{
                if fm.fileExists(atPath:target.path){continue}
                throw error
            }
        }
        throw CaptureFailure.message("同名文件过多，请使用另存为。")
    }
}
