import AppKit
import QuartzCore
enum SelectionMode {case region,window,screen}
final class SelectionWindow:NSWindow {
    override var canBecomeKey:Bool{true}
    override var canBecomeMain:Bool{false}
}
final class SelectionView:NSView {
    unowned let session:SelectionSession
    let snapshot:DisplaySnapshot
    private var tracking:NSTrackingArea?
    init(session:SelectionSession,snapshot:DisplaySnapshot){
        self.session=session;self.snapshot=snapshot
        super.init(frame:.init(origin:.zero,size:snapshot.frame.size))
    }
    required init?(coder:NSCoder){fatalError()}
    override var acceptsFirstResponder:Bool{true}
    override func updateTrackingAreas(){
        if let tracking=tracking{removeTrackingArea(tracking)}
        tracking=NSTrackingArea(rect:bounds,options:[.mouseMoved,.activeAlways,.inVisibleRect],owner:self)
        addTrackingArea(tracking!);super.updateTrackingAreas()
    }
    override func draw(_ dirtyRect:NSRect){
        let image=NSImage(cgImage:snapshot.image,size:bounds.size);image.draw(in:bounds)
        let path=NSBezierPath(rect:bounds)
        if let s=session.selection ?? session.candidate {
            let local=s.offsetBy(dx:-snapshot.frame.minX,dy:-snapshot.frame.minY)
            if local.intersects(bounds) {
                path.appendRect(local);path.windingRule = .evenOdd
            }
        }
        NSColor.black.withAlphaComponent(0.43).setFill();path.fill()
        guard let selected=session.selection ?? session.candidate else{return}
        let r=selected.offsetBy(dx:-snapshot.frame.minX,dy:-snapshot.frame.minY)
        NSColor.black.setStroke();let outer=NSBezierPath(rect:r);outer.lineWidth=3;outer.stroke()
        NSColor.white.setStroke();outer.lineWidth=1;outer.stroke()
        if session.selection != nil {
            let points=[CGPoint(x:r.minX,y:r.minY),.init(x:r.midX,y:r.minY),.init(x:r.maxX,y:r.minY),.init(x:r.maxX,y:r.midY),.init(x:r.maxX,y:r.maxY),.init(x:r.midX,y:r.maxY),.init(x:r.minX,y:r.maxY),.init(x:r.minX,y:r.midY)]
            for p in points {
                let h=NSBezierPath(ovalIn:.init(x:p.x-4,y:p.y-4,width:8,height:8))
                NSColor.black.setFill();h.fill();NSColor.white.setStroke();h.lineWidth=1.5;h.stroke()
            }
        }
        let size=session.pixelSize(selected)
        let text="\(size.0) × \(size.1) px"
        let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.monospacedDigitSystemFont(ofSize:12,weight:.medium),.foregroundColor:NSColor.white]
        let textSize=(text as NSString).size(withAttributes:attrs)
        let box=CGRect(sl_clamp(CGRect(x:r.minX,y:r.maxY+8,width:textSize.width+16,height:26).sl,bounds.insetBy(dx:6,dy:6).sl))
        NSColor(white:0.1,alpha:0.92).setFill();NSBezierPath(roundedRect:box,xRadius:6,yRadius:6).fill()
        (text as NSString).draw(at:.init(x:box.minX+8,y:box.minY+6),withAttributes:attrs)
    }
    private func screenPoint(_ event:NSEvent)->CGPoint {
        window?.convertPoint(toScreen:event.locationInWindow) ?? NSEvent.mouseLocation
    }
    override func mouseDown(with event:NSEvent){session.down(at:screenPoint(event))}
    override func mouseDragged(with event:NSEvent){session.drag(to:screenPoint(event))}
    override func mouseUp(with event:NSEvent){session.up(at:screenPoint(event))}
    override func mouseMoved(with event:NSEvent){session.hover(at:screenPoint(event))}
    override func keyDown(with event:NSEvent){session.key(event)}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.crosshair)}
}
final class SelectionSession:NSObject {
    let snapshots:[DisplaySnapshot]
    let started:Double
    let sessionID=UUID().uuidString
    var selection:CGRect?
    var candidate:CGRect?
    var onFinish:((String?)->Void)?
    var onRecord:((RecordingRegion?)->Void)?
    private let recordingSelection:Bool
    private var ocr:OCRPanel?
    private var transfer:AirDropTransfer?
    private var smart:SmartSelection?
    var onChooseFolder:(()->URL?)?
    private var windows=[SelectionWindow]()
    private var toolbar:NSPanel?
    private var toolbarSize=NSSize(width:590,height:44)
    private var modebar:NSPanel?
    private var startPoint=CGPoint.zero
    private var original:CGRect?
    private var handle:Int32 = -1
    private var moving=false
    private var dragging=false
    private var suspended=false
    private var exporting=false
    private var mode:SelectionMode
    private let candidates:[CGRect]
    var bounds:CGRect{snapshots.reduce(CGRect.null){$0.union($1.frame)}}
    init(snapshots:[DisplaySnapshot],started:Double,mode:SelectionMode,candidates:[DesktopWindowTarget],recordingSelection:Bool=false){
        self.recordingSelection=recordingSelection
        self.snapshots=snapshots;self.started=started;self.mode=mode;self.candidates=candidates.map(\.frame)
        super.init()
        if !candidates.isEmpty{smart=SmartSelection(targets:candidates)}
        if mode == .screen{selection=(snapshots.first(where:{$0.frame.contains(NSEvent.mouseLocation)}) ?? snapshots.first)?.frame}
        if mode == .window{candidate=self.candidates.first(where:{$0.contains(NSEvent.mouseLocation)})}
    }
    func present(){
        NSApp.activate(ignoringOtherApps:true)
        for snapshot in snapshots {
            let window=SelectionWindow(contentRect:snapshot.frame,styleMask:.borderless,backing:.buffered,defer:false)
            window.isOpaque=true;window.backgroundColor = .black;window.hasShadow=false
            window.level=NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue+1)
            window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
            window.isReleasedWhenClosed=false;window.acceptsMouseMovedEvents=true
            let v=SelectionView(session:self,snapshot:snapshot);window.contentView=v
            window.orderFrontRegardless();window.makeFirstResponder(v);window.displayIfNeeded()
            windows.append(window)
        }
        let key=windows.first(where:{$0.frame.contains(NSEvent.mouseLocation)}) ?? windows.first
        key?.makeKey();key?.makeFirstResponder(key?.contentView)
        buildBars();refresh()
        CATransaction.flush()
        DispatchQueue.main.async{ [weak self] in
            guard let self=self else{return}
            Metrics.shared.write("selectable",["session":self.sessionID,"ms":(now()-self.started)*1000,"measurement":"runloop_after_window_submission; physical presentation not measured"])
        }
        NotificationCenter.default.addObserver(self,selector:#selector(topologyChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(topologyChanged),name:NSWorkspace.willSleepNotification,object:nil)
    }
    func pixelSize(_ rect:CGRect)->(Int,Int){
        let parts=snapshots.filter{$0.frame.intersects(rect)}
        if parts.count==1 {
            let p=CGRect(sl_pixels(rect.sl,parts[0].frame.sl,Double(parts[0].image.width),Double(parts[0].image.height)))
            return (Int(p.width),Int(p.height))
        }
        let scale=parts.map(\.scale).max() ?? 1
        return (Int(ceil(rect.width*scale)),Int(ceil(rect.height*scale)))
    }
    private func bar(_ size:NSSize)->NSPanel{
        let p=OrbPanel(contentRect:.init(origin:.zero,size:size),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=true;p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false
        p.level=NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue+2)
        p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        let material=materialView(radius:13);material.frame = .init(origin:.zero,size:size);p.contentView=material
        return p
    }
    private func button(_ title:String,_ selector:Selector)->NSButton{
        let b=NSButton(title:title,target:self,action:selector);b.bezelStyle = .recessed;b.font = .systemFont(ofSize:13,weight:.medium)
        b.setAccessibilityLabel(title);return b
    }
    private func buildBars(){
        toolbar=bar(toolbarSize)
        let buttons=recordingSelection ? [button("取消",#selector(cancel)),button("使用此区域 ↵",#selector(recordMode))] : [button("提取文字",#selector(extractText)),button("复制",#selector(copyImage)),button("AirDrop",#selector(airDrop)),button("下载 ▾",#selector(downloadMenu(_:))),button("取消",#selector(cancel)),button("完成 ↵",#selector(copyImage))]
        let separator=NSBox();separator.boxType = .separator;separator.widthAnchor.constraint(equalToConstant:1).isActive=true;separator.heightAnchor.constraint(equalToConstant:20).isActive=true
        let views:[NSView]=recordingSelection ? buttons : Array(buttons.prefix(4))+[separator]+Array(buttons.suffix(2))
        let stack=NSStackView(views:views);stack.spacing=10;stack.orientation = .horizontal;stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints=false;toolbar!.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo:toolbar!.contentView!.centerXAnchor),stack.centerYAnchor.constraint(equalTo:toolbar!.contentView!.centerYAnchor)])
        toolbarSize.width=ceil(stack.fittingSize.width)+32
        toolbar?.setContentSize(toolbarSize)
        modebar=bar(.init(width:260,height:42))
        let modes=NSStackView(views:recordingSelection ? [NSTextField(labelWithString:"框选录制区域 · 单个显示器")] : [button("截图",#selector(screenshotMode)),button("屏幕录制",#selector(recordMode))])
        modes.spacing=18;modes.frame = .init(x:18,y:7,width:224,height:28);modebar!.contentView!.addSubview(modes)
        let screen=NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)}) ?? NSScreen.main
        if let screen=screen{modebar!.setFrameOrigin(.init(x:screen.visibleFrame.midX-130,y:screen.visibleFrame.maxY-56))}
        modebar?.orderFrontRegardless()
    }
    func refresh(){
        for w in windows{w.contentView?.needsDisplay=true}
        guard !suspended else{return}
        if let s=selection {
            let screen=NSScreen.screens.max(by:{$0.frame.intersection(s).area < $1.frame.intersection(s).area})
            if let visible=screen?.visibleFrame.insetBy(dx:8,dy:8) {
                let r=CGRect(sl_toolbar(s.sl,visible.sl,Double(toolbarSize.width),Double(toolbarSize.height),12));toolbar?.setFrame(r,display:true)
            }
            toolbar?.orderFrontRegardless()
        }else{toolbar?.orderOut(nil)}
    }
    func down(at p:CGPoint){
        guard !exporting else{return}
        startPoint=p;original=selection;dragging=false;handle = -1;moving=false
        if let s=selection {
            handle=sl_handle(s.sl,p.sl,9)
            moving=handle<0 && s.contains(p)
            if !moving && handle<0{selection=nil;original=nil}
        }
    }
    func drag(to p:CGPoint){
        guard !exporting else{return}
        if hypot(p.x-startPoint.x,p.y-startPoint.y)<3 && !dragging{return}
        dragging=true;candidate=nil
        if let s=original,handle>=0 {
            selection=CGRect(sl_intersect(sl_resize(s.sl,SLPoint(x:p.x-startPoint.x,y:p.y-startPoint.y),handle,1),bounds.sl))
        }else if let s=original,moving{
            selection=CGRect(sl_clamp(s.offsetBy(dx:p.x-startPoint.x,dy:p.y-startPoint.y).sl,bounds.sl))
        }else{
            mode = .region;selection=CGRect(sl_intersect(sl_normalize(startPoint.sl,p.sl),bounds.sl))
        }
        toolbar?.orderOut(nil)
        for w in windows{w.contentView?.needsDisplay=true}
    }
    func up(at p:CGPoint){
        if !dragging,selection==nil,let candidate=candidate{selection=candidate.intersection(bounds)}
        if let s=selection,s.width<1||s.height<1{selection=nil}
        refresh()
    }
    func hover(at p:CGPoint){
        guard selection==nil,!dragging,!suspended else{return}
        smart?.hit(p){ [weak self] next in
            guard let self=self,self.selection==nil,!self.dragging,!self.suspended else{return}
            if next != self.candidate{self.candidate=next;self.refresh()}
        }
    }
    func key(_ e:NSEvent){
        guard !suspended,!exporting else{return}
        if e.keyCode==53{cancel();return}
        if e.keyCode==36 || e.keyCode==76{recordingSelection ? recordMode():copyImage();return}
        if recordingSelection,e.modifierFlags.contains(.command){return}
        if e.modifierFlags.contains(.command),e.charactersIgnoringModifiers=="c"{copyImage();return}
        if e.modifierFlags.contains(.command),e.charactersIgnoringModifiers=="s"{save();return}
        if e.charactersIgnoringModifiers=="h"{toolbar?.isVisible==true ? toolbar?.orderOut(nil):refresh();return}
        guard var r=selection else{return}
        let step:CGFloat=e.modifierFlags.contains(.shift) ? 10:1
        switch e.keyCode {
        case 123: if e.modifierFlags.contains(.option){r.size.width=max(1,r.width-step)}else{r.origin.x-=step}
        case 124: if e.modifierFlags.contains(.option){r.size.width+=step}else{r.origin.x+=step}
        case 125: if e.modifierFlags.contains(.option){r.size.height=max(1,r.height-step)}else{r.origin.y-=step}
        case 126: if e.modifierFlags.contains(.option){r.size.height+=step}else{r.origin.y+=step}
        default:return
        }
        selection=CGRect(sl_clamp(r.sl,bounds.sl));refresh()
    }
    private func hideForDialog(){
        suspended=true;windows.forEach{$0.orderOut(nil)};toolbar?.orderOut(nil);modebar?.orderOut(nil)
    }
    private func restoreAfterDialog(){
        suspended=false;windows.forEach{$0.orderFrontRegardless()};windows.first?.makeKey();modebar?.orderFrontRegardless();refresh()
    }
    private func failure(_ error:Error){hideForDialog();showError(error.localizedDescription);restoreAfterDialog()}
    @objc func copyImage(){
        guard !exporting,let r=selection else{return}
        exporting=true;let t=now()
        do{
            let image=try CaptureBackend.crop(r,from:snapshots)
            try CaptureBackend.copy(image)
            Metrics.shared.write("clipboard_complete",["session":sessionID,"ms":(now()-t)*1000,"width":image.width,"height":image.height])
            finish("已复制图片")
        }catch{exporting=false;failure(error)}
    }
    @objc func downloadMenu(_ sender:NSButton){
        let m=NSMenu()
        for (title,action) in [("保存",#selector(save)),("另存为…",#selector(saveAs)),("默认保存位置设置…",#selector(chooseFolder))]{
            let item=NSMenuItem(title:title,action:action,keyEquivalent:"");item.target=self;m.addItem(item)
        }
        m.popUp(positioning:nil,at:.init(x:0,y:sender.bounds.maxY+6),in:sender)
    }
    @objc func chooseFolder(){
        hideForDialog();_ = onChooseFolder?();restoreAfterDialog()
    }
    @objc func save(){
        guard let r=selection,!exporting else{return}
        var folder=Preferences.shared.folderURL
        if folder==nil{hideForDialog();folder=onChooseFolder?();restoreAfterDialog()}
        guard let folder=folder else{return}
        exporting=true
        do{let image=try CaptureBackend.crop(r,from:snapshots);_ = try CaptureBackend.save(image,to:folder);finish("已保存图片")}
        catch{exporting=false;failure(CaptureFailure.message("保存失败：\(error.localizedDescription)\n请检查文件夹权限、磁盘空间，或使用另存为。"))}
    }
    @objc func saveAs(){
        guard let r=selection,!exporting else{return}
        hideForDialog()
        let panel=NSSavePanel();panel.title="保存截图";panel.nameFieldStringValue="Snapliq.png";panel.allowedContentTypes=[.png];panel.canCreateDirectories=true
        panel.directoryURL=Preferences.shared.folderURL
        let response=panel.runModal()
        guard response == .OK,let url=panel.url else{restoreAfterDialog();return}
        exporting=true
        do{let image=try CaptureBackend.crop(r,from:snapshots);try CaptureBackend.png(image).write(to:url,options:.atomic);finish("已保存图片")}
        catch{exporting=false;showError(error.localizedDescription);restoreAfterDialog()}
    }
    @objc private func screenshotMode(){}
    @objc private func recordMode(){
        guard !exporting,!suspended else{return}
        if recordingSelection && selection==nil{NSSound.beep();return}
        do {
            let region=try selection.map{try RecordingRegion.resolve($0,snapshots:snapshots)}
            let action=onRecord;finish(nil);action?(region)
        }catch{failure(error)}
    }
    @objc private func extractText(){
        guard let r=selection,!exporting else{return}
        do {
            let image=try CaptureBackend.crop(r,from:snapshots);hideForDialog()
            let panel=OCRPanel(image:image);ocr=panel
            panel.onClose={ [weak self] in self?.ocr=nil;self?.restoreAfterDialog() }
        }catch{failure(error)}
    }
    @objc private func airDrop(){
        guard let r=selection,!exporting else{return}
        do {
            let image=try CaptureBackend.crop(r,from:snapshots);hideForDialog()
            let transfer=AirDropTransfer();self.transfer=transfer
            transfer.share(image){[weak self] error in
                guard let self=self else{return};self.transfer=nil
                if let error=error{showError(error)};self.restoreAfterDialog()
            }
        }catch{failure(error)}
    }
    @objc func topologyChanged(){finish("显示器变化或系统即将休眠，截图已取消")}
    @objc func cancel(){finish(nil)}
    func finish(_ message:String?){
        smart?.cancel();smart=nil;ocr?.onClose=nil;ocr?.close();ocr=nil;transfer=nil
        NotificationCenter.default.removeObserver(self);NSWorkspace.shared.notificationCenter.removeObserver(self)
        windows.forEach{$0.orderOut(nil);$0.close()};windows.removeAll()
        toolbar?.close();toolbar=nil;modebar?.close();modebar=nil
        let completion=onFinish;onFinish=nil;completion?(message)
    }
}
