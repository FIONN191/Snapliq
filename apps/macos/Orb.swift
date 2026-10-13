import AppKit

/// Logical points, including negative monitor origins. Insets respect tiny work areas.
enum OrbLayout {
    static func frame(center:CGPoint,size:CGFloat,within visible:CGRect,snap:Bool)->CGRect {
        let side=min(size,visible.width,visible.height)
        let insetX=min(10,max(0,(visible.width-side)/2)),insetY=min(10,max(0,(visible.height-side)/2))
        let area=visible.insetBy(dx:insetX,dy:insetY)
        var x=min(max(center.x-side/2,area.minX),area.maxX-side)
        var y=min(max(center.y-side/2,area.minY),area.maxY-side)
        if snap {
            let distances=[x-area.minX,area.maxX-side-x,y-area.minY,area.maxY-side-y]
            switch distances.enumerated().min(by:{$0.element<$1.element})!.offset {
            case 0:x=area.minX
            case 1:x=area.maxX-side
            case 2:y=area.minY
            default:y=area.maxY-side
            }
        }
        return CGRect(x:x,y:y,width:side,height:side)
    }
    static func normalizedCenter(of frame:CGRect,in visible:CGRect)->CGPoint {
        CGPoint(x:(frame.midX-visible.minX)/max(1,visible.width),y:(frame.midY-visible.minY)/max(1,visible.height))
    }
    static func restoredFrame(size:CGFloat,within visible:CGRect,normalized:CGPoint,snap:Bool)->CGRect {
        let x=normalized.x.isFinite ? min(1,max(0,normalized.x)):0.5
        let y=normalized.y.isFinite ? min(1,max(0,normalized.y)):0.5
        return frame(center:CGPoint(x:visible.minX+visible.width*x,y:visible.minY+visible.height*y),size:size,within:visible,snap:snap)
    }
}
struct OrbDragGesture {
    let start:CGPoint,origin:CGPoint,locked:Bool
    private(set) var dragged=false
    mutating func move(to point:CGPoint)->CGPoint? {
        if hypot(point.x-start.x,point.y-start.y)>4{dragged=true}
        guard dragged,!locked else{return nil}
        return CGPoint(x:origin.x+point.x-start.x,y:origin.y+point.y-start.y)
    }
    var shouldCapture:Bool{!dragged}
}
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
            NSGraphicsContext.current?.cgContext.scaleBy(x:bounds.width/48,y:bounds.height/48)
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
    var positionLocked=false
    let decorations=OrbDecorations()
    var recordingState="idle"{didSet{decorations.recordingState=recordingState;decorations.needsDisplay=true}}
    private var tracking:NSTrackingArea?
    override func updateTrackingAreas(){
        if let tracking=tracking{removeTrackingArea(tracking)}
        tracking=NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.activeAlways],owner:self)
        addTrackingArea(tracking!);super.updateTrackingAreas()
    }
    override func mouseEntered(with event:NSEvent){decorations.hovering=true;decorations.needsDisplay=true}
    override func mouseExited(with event:NSEvent){decorations.hovering=false;decorations.needsDisplay=true}
    override func mouseDown(with event:NSEvent){
        guard let window=window else{return}
        var gesture=OrbDragGesture(start:NSEvent.mouseLocation,origin:window.frame.origin,locked:positionLocked)
        while let next=window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]){
            if let origin=gesture.move(to:NSEvent.mouseLocation){window.setFrameOrigin(origin)}
            if next.type == .leftMouseUp{break}
        }
        if gesture.dragged && !positionLocked{onMoved?()}else if gesture.shouldCapture{onClick?()}
    }
    override func rightMouseDown(with event:NSEvent){if let context=context{NSMenu.popUpContextMenu(context,with:event,for:self)}}
    override func hitTest(_ point:NSPoint)->NSView?{bounds.contains(point) ? self:nil}
}
final class OrbController:NSObject {
    let panel:OrbPanel
    let view=OrbView(frame:.init(x:0,y:0,width:48,height:48))
    private let preferences:Preferences
    private let symbol=BrandView()
    private var material:NSView?
    private var materialDiameter:CGFloat=0
    private var lastSnap=true
    private var lockItem:NSMenuItem!
    var onCapture:(()->Void)?
    var onSettings:(()->Void)?
    var onStateChanged:(()->Void)?
    private var timer:Timer?
    init(preferences:Preferences = .shared){
        self.preferences=preferences
        panel=OrbPanel(contentRect:.init(x:0,y:0,width:48,height:48),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        super.init()
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.level = .statusBar
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]
        panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false
        view.addSubview(symbol)
        view.decorations.autoresizingMask=[.width,.height];view.addSubview(view.decorations)
        panel.contentView=view;panel.setAccessibilityIdentifier("snapliq.orb.window")
        view.setAccessibilityElement(true);view.setAccessibilityRole(.button);view.setAccessibilityLabel("Snapliq 截图，右键打开设置菜单")
        view.setAccessibilityIdentifier("snapliq.orb")
        view.onClick={ [weak self] in self?.onCapture?() }
        view.onMoved={ [weak self] in self?.dockAndSave() }
        let menu=NSMenu()
        for (title,sel) in [("仅今天停用",#selector(today)),("停用",#selector(disable))] {
            let item=NSMenuItem(title:title,action:sel,keyEquivalent:"");item.target=self;menu.addItem(item)
        }
        menu.addItem(.separator())
        lockItem=NSMenuItem(title:"锁定当前位置",action:#selector(toggleLock),keyEquivalent:"");lockItem.target=self;menu.addItem(lockItem)
        let settings=NSMenuItem(title:"设置",action:#selector(settings),keyEquivalent:"");settings.target=self;menu.addItem(settings);view.context=menu
        NotificationCenter.default.addObserver(self,selector:#selector(revalidate),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(revalidate),name:NSNotification.Name.NSSystemTimeZoneDidChange,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(revalidate),name:.NSCalendarDayChanged,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(revalidate),name:NSWorkspace.didWakeNotification,object:nil)
        timer=Timer.scheduledTimer(withTimeInterval:60,repeats:true){[weak self] _ in self?.refresh()}
        lastSnap=preferences.orbSnapToEdge;restorePosition()
    }
    deinit{timer?.invalidate();NotificationCenter.default.removeObserver(self);NSWorkspace.shared.notificationCenter.removeObserver(self)}
    private func screenID(_ s:NSScreen)->String{String((s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0)}
    private func currentScreen()->NSScreen? {
        if let screen=NSScreen.screens.max(by:{$0.frame.intersection(panel.frame).area < $1.frame.intersection(panel.frame).area}),screen.frame.intersection(panel.frame).area>0{return screen}
        return NSScreen.screens.min{hypot($0.frame.midX-panel.frame.midX,$0.frame.midY-panel.frame.midY)<hypot($1.frame.midX-panel.frame.midX,$1.frame.midY-panel.frame.midY)}
    }
    private func setFrame(_ frame:CGRect){
        panel.setFrame(frame,display:true)
        view.frame=CGRect(origin:.zero,size:frame.size)
        if materialDiameter != frame.width {
            material?.removeFromSuperview()
            let next=materialView(radius:frame.width/2);next.frame=view.bounds;next.autoresizingMask=[.width,.height]
            view.addSubview(next,positioned:.below,relativeTo:symbol);material=next;materialDiameter=frame.width
        }
        symbol.frame=view.bounds.insetBy(dx:frame.width/6,dy:frame.height/6)
        view.decorations.frame=view.bounds;view.decorations.needsDisplay=true
        view.positionLocked=preferences.orbPositionLocked
        lockItem.state=preferences.orbPositionLocked ? .on:.off
        view.setAccessibilityHelp(preferences.orbPositionLocked ? "位置已锁定。点击截图；右键可解锁或打开设置。":"点击截图；拖动调整位置；右键打开菜单。")
    }
    func restorePosition(){
        let d=preferences.defaults
        guard let screen=NSScreen.screens.first(where:{screenID($0)==d.string(forKey:"orbScreen")}) ?? NSScreen.main else{return}
        let f=screen.visibleFrame,size=CGFloat(preferences.orbSize)
        let frame:CGRect
        if d.object(forKey:"orbNormalizedX") != nil && d.object(forKey:"orbNormalizedY") != nil {
            frame=OrbLayout.restoredFrame(size:size,within:f,normalized:.init(x:d.double(forKey:"orbNormalizedX"),y:d.double(forKey:"orbNormalizedY")),snap:preferences.orbSnapToEdge && !preferences.orbPositionLocked && d.bool(forKey:"orbWasDocked"))
        } else {
            // Migrate the old left/right edge + vertical fraction without losing the user's placement.
            let area=f.insetBy(dx:10,dy:10)
            let fraction=d.object(forKey:"orbFraction")==nil ? 0.35:d.double(forKey:"orbFraction")
            let y=area.minY+max(0,area.height-size)*min(1,max(0,fraction))
            let x=d.string(forKey:"orbEdge")=="left" ? area.minX:area.maxX-size
            frame=OrbLayout.frame(center:.init(x:x+size/2,y:y+size/2),size:size,within:f,snap:false)
        }
        setFrame(frame);savePosition(on:screen)
    }
    /// Settings apply immediately. Lock takes precedence over snapping; a size change retains the center where it fits.
    func applyPreferences(){
        guard let screen=currentScreen() else{return}
        let changedSnap=lastSnap != preferences.orbSnapToEdge
        let changedSize=abs(panel.frame.width-CGFloat(preferences.orbSize))>0.01
        let shouldSnap=preferences.orbSnapToEdge && !preferences.orbPositionLocked && (changedSnap || changedSize)
        let frame=OrbLayout.frame(center:.init(x:panel.frame.midX,y:panel.frame.midY),size:CGFloat(preferences.orbSize),within:screen.visibleFrame,snap:shouldSnap)
        setFrame(frame);lastSnap=preferences.orbSnapToEdge;savePosition(on:screen);refresh()
    }
    func dockAndSave(){
        guard let screen=currentScreen() else{return}
        setFrame(OrbLayout.frame(center:.init(x:panel.frame.midX,y:panel.frame.midY),size:CGFloat(preferences.orbSize),within:screen.visibleFrame,snap:preferences.orbSnapToEdge && !preferences.orbPositionLocked))
        savePosition(on:screen)
    }
    private func savePosition(on screen:NSScreen){
        let point=OrbLayout.normalizedCenter(of:panel.frame,in:screen.visibleFrame),d=preferences.defaults
        d.set(screenID(screen),forKey:"orbScreen");d.set(Double(point.x),forKey:"orbNormalizedX");d.set(Double(point.y),forKey:"orbNormalizedY")
        let docked=OrbLayout.frame(center:.init(x:panel.frame.midX,y:panel.frame.midY),size:panel.frame.width,within:screen.visibleFrame,snap:true)
        // Restore real docking only; unlocking a freely positioned orb must not move it after restart.
        d.set(hypot(docked.minX-panel.frame.minX,docked.minY-panel.frame.minY)<0.01,forKey:"orbWasDocked")
    }
    var temporarilyHidden=false
    func refresh(){
        preferences.validateDate()
        if !temporarilyHidden && !preferences.orbHidden && !preferences.orbDisabledToday{panel.orderFrontRegardless()}
        else{panel.orderOut(nil)}
    }
    @objc func revalidate(){restorePosition();refresh();onStateChanged?()}
    @objc func today(){preferences.disableToday();refresh();onStateChanged?()}
    @objc func disable(){preferences.orbHidden=true;refresh();onStateChanged?()}
    @objc func toggleLock(){preferences.orbPositionLocked.toggle();applyPreferences();onStateChanged?()}
    @objc func settings(){onSettings?()}
    func restore(){preferences.restoreOrb();refresh();onStateChanged?()}
}
extension CGRect {var area:CGFloat{isNull ? 0:width*height}}
