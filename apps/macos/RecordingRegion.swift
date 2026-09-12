import AppKit

/// A fixed display-local crop. Source points and encoded pixels are deliberately separate.
struct RecordingRegion {
    let displayID:CGDirectDisplayID
    let displayFrame:CGRect
    let scale:CGFloat
    let sourceRect:CGRect
    let pixelWidth:Int
    let pixelHeight:Int

    init(selection:CGRect,displayID:CGDirectDisplayID,displayFrame:CGRect,scale:CGFloat)throws {
        let numbers=[selection.minX,selection.minY,selection.width,selection.height,
                     displayFrame.minX,displayFrame.minY,displayFrame.width,displayFrame.height,scale]
        guard numbers.allSatisfy({$0.isFinite}),scale>0,scale<=8,
              displayFrame.width>0,displayFrame.height>0,selection.width>0,selection.height>0,
              displayFrame.contains(selection) else {
            throw CaptureFailure.message("区域录屏需要在同一个显示器内框选，请重新选择。")
        }
        let left=ceil((selection.minX-displayFrame.minX)*scale)
        let top=ceil((displayFrame.maxY-selection.maxY)*scale)
        let right=floor((selection.maxX-displayFrame.minX)*scale)
        let bottom=floor((displayFrame.maxY-selection.minY)*scale)
        let width=floor((right-left)/2)*2,height=floor((bottom-top)/2)*2
        guard width>=2,height>=2,width<=32768,height<=32768 else {
            throw CaptureFailure.message("录制区域过小或过大，请选择至少 2 × 2 像素的区域。")
        }
        self.displayID=displayID;self.displayFrame=displayFrame;self.scale=scale
        sourceRect=CGRect(x:left/scale,y:top/scale,width:width/scale,height:height/scale)
        pixelWidth=Int(width);pixelHeight=Int(height)
    }

    static func resolve(_ selection:CGRect,snapshots:[DisplaySnapshot])throws->RecordingRegion {
        guard let display=snapshots.first(where:{$0.frame.contains(selection)}) else {
            throw CaptureFailure.message("本版区域录屏暂不支持跨屏选区，请在一个显示器内重新框选。")
        }
        return try RecordingRegion(selection:selection,displayID:display.id,displayFrame:display.frame,scale:display.scale)
    }

    func validate(frame:CGRect,pointPixelScale:CGFloat)throws {
        guard frame==displayFrame,abs(pointPixelScale-scale)<0.001 else {
            throw CaptureFailure.message("显示器或缩放设置已变化，请重新框选录制区域。")
        }
    }

    func validateCurrentDisplay(pointPixelScale:CGFloat)throws {
        guard let screen=NSScreen.screens.first(where:{
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value==displayID
        }) else{throw CaptureFailure.message("录制区域所在的显示器已断开，请重新选择。")}
        try validate(frame:screen.frame,pointPixelScale:pointPixelScale)
    }
}
