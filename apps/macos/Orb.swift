import AppKit
final class OrbPanel:NSPanel {
    override var canBecomeKey:Bool{false}
    override var canBecomeMain:Bool{false}
}
final class OrbDecorations:NSView {
    var recordingState="idle",hovering=false
    override func draw(_ rect:NSRect){
        NSGraphicsContext.saveGraphicsState()
        let p=NSBezierPath(ovalIn:bounds.insetBy(dx:1,dy:1))
        NSColor.labelColor.withAlphaComponent(hovering ? 0.35:0.14).setStroke();p.lineWidth=1;p.stroke()
        if recordingState != "idle" {
            let badge=CGRect(x:31,y:2,width:14,height:14)
            NSColor.windowBackgroundColor.setFill();NSBezierPath(ovalIn:badge).fill()
            NSColor.labelColor.setFill()
            if recordingState == "paused" {NSRect(x:35,y:5,width:2,height:8).fill();NSRect(x:39,y:5,width:2,height:8).fill()}
            else if recordingState == "recording"{NSBezierPath(ovalIn:badge.insetBy(dx:4,dy:4)).fill()}
            else if recordingState == "finishing"{badge.insetBy(dx:4,dy:4).fill()}
            else{NSColor.labelColor.setStroke();NSBezierPath(ovalIn:badge.insetBy(dx:4,dy:4)).stroke()}
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
final class OrbView:NSView {
    var onClick:(()->Void)?
    var onMoved:(()->Void)?
    var context:NSMenu?
    let decorations=OrbDecorations()
    var recordingState="idle"{didSet{decorations.recordingState=recordingState;decorations.needsDisplay=true}}
    private var hovering=false
    private var tracking:NSTrackingArea?
    override func updateTrackingAreas(){
        if let tracking=tracking{removeTrackingArea(tracking)}
        tracking=NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.activeAlways],owner:self)
        addTrackingArea(tracking!);super.updateTrackingAreas()
    }
    override func mouseEntered(with event:NSEvent){hovering=true;decorations.hovering=true;decorations.needsDisplay=true}
    override func mouseExited(with event:NSEvent){hovering=false;decorations.hovering=false;decorations.needsDisplay=true}
    override func mouseDown(with event:NSEvent){
        guard let window=window else{return}
        let start=NSEvent.mouseLocation,origin=window.frame.origin
        var moved=false
        while let next=window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]){
            if next.type == .leftMouseUp{break}
            let point=NSEvent.mouseLocation
            if hypot(point.x-start.x,point.y-start.y)>4{moved=true}
            if moved{window.setFrameOrigin(.init(x:origin.x+point.x-start.x,y:origin.y+point.y-start.y))}
        }
        if moved{onMoved?()}else{onClick?()}
    }
    override func rightMouseDown(with event:NSEvent){if let context=context{NSMenu.popUpContextMenu(context,with:event,for:self)}}
    override func hitTest(_ point:NSPoint)->NSView?{bounds.contains(point) ? self:nil}
}
final class OrbController:NSObject {
    let panel:OrbPanel
    let view=OrbView(frame:.init(x:0,y:0,width:48,height:48))
    var onCapture:(()->Void)?
    var onSettings:(()->Void)?
    var onStateChanged:(()->Void)?
    private var timer:Timer?
    override init(){
        panel=OrbPanel(contentRect:.init(x:0,y:0,width:48,height:48),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        super.init()
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.level = .statusBar
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]
        panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false
        let material=materialView(radius:24);material.frame=view.bounds;material.autoresizingMask=[.width,.height]
        view.addSubview(material)
        let symbol=BrandView(frame:.init(x:8,y:8,width:32,height:32));view.addSubview(symbol)
        view.decorations.frame=view.bounds;view.decorations.autoresizingMask=[.width,.height];view.addSubview(view.decorations)
        panel.contentView=view
        view.setAccessibilityElement(true);view.setAccessibilityRole(.button);view.setAccessibilityLabel("Snapliq 截图，右键打开设置菜单")
        view.onClick={ [weak self] in self?.onCapture?() }
        view.onMoved={ [weak self] in self?.dockAndSave() }
        let menu=NSMenu()
        for (title,sel) in [("仅今天停用",#selector(today)),("停用",#selector(disable))] {
            let item=NSMenuItem(title:title,action:sel,keyEquivalent:"");item.target=self;menu.addItem(item)
        }
        menu.addItem(.separator())
        let settings=NSMenuItem(title:"设置",action:#selector(settings),keyEquivalent:"");settings.target=self;menu.addItem(settings);view.context=menu
        NotificationCenter.default.addObserver(self,selector:#selector(revalidate),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(revalidate),name:NSNotification.Name.NSSystemTimeZoneDidChange,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(revalidate),name:.NSCalendarDayChanged,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(revalidate),name:NSWorkspace.didWakeNotification,object:nil)
        // Low-frequency wall-clock revalidation also covers manual time changes.
        timer=Timer.scheduledTimer(withTimeInterval:60,repeats:true){[weak self] _ in self?.refresh()}
        restorePosition()
    }
    private func screenID(_ s:NSScreen)->String{String((s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0)}
    func restorePosition(){
        let d=Preferences.shared.defaults
        guard let screen=NSScreen.screens.first(where:{screenID($0)==d.string(forKey:"orbScreen")}) ?? NSScreen.main else{return}
        let frame=screen.visibleFrame.insetBy(dx:10,dy:10)
        let fraction=d.object(forKey:"orbFraction")==nil ? 0.35:d.double(forKey:"orbFraction")
        let x=d.string(forKey:"orbEdge")=="left" ? frame.minX:frame.maxX-48
        panel.setFrameOrigin(.init(x:x,y:frame.minY+max(0,frame.height-48)*min(1,max(0,fraction))))
    }
    func dockAndSave(){
        guard let screen=NSScreen.screens.max(by:{$0.frame.intersection(panel.frame).area < $1.frame.intersection(panel.frame).area}) else{return}
        let f=screen.visibleFrame.insetBy(dx:10,dy:10),left=panel.frame.midX<f.midX
        let r=CGRect(sl_clamp(panel.frame.sl,f.sl));panel.setFrameOrigin(.init(x:left ? f.minX:f.maxX-48,y:r.minY))
        let d=Preferences.shared.defaults;d.set(screenID(screen),forKey:"orbScreen");d.set(left ? "left":"right",forKey:"orbEdge")
        d.set((panel.frame.minY-f.minY)/max(1,f.height-48),forKey:"orbFraction")
    }
    var temporarilyHidden=false
    func refresh(){
        Preferences.shared.validateDate()
        if !temporarilyHidden && !Preferences.shared.orbHidden && !Preferences.shared.orbDisabledToday{panel.orderFrontRegardless()}
        else{panel.orderOut(nil)}
    }
    @objc func revalidate(){restorePosition();refresh();onStateChanged?()}
    @objc func today(){Preferences.shared.disableToday();refresh();onStateChanged?()}
    @objc func disable(){Preferences.shared.orbHidden=true;refresh();onStateChanged?()}
    @objc func settings(){onSettings?()}
    func restore(){Preferences.shared.restoreOrb();refresh();onStateChanged?()}
}
extension CGRect {var area:CGFloat{isNull ? 0:width*height}}
