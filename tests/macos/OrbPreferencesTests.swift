import AppKit

/// Isolated preferences and hidden native windows only: no capture, global input, or real app settings.
@main struct OrbPreferencesTests {
    static var checks=0
    static func expect(_ condition:@autoclosure ()->Bool,_ message:String){
        checks+=1
        precondition(condition(),message)
    }
    static func near(_ a:CGFloat,_ b:CGFloat)->Bool{abs(a-b)<0.001}
    static func same(_ a:CGPoint,_ b:CGPoint)->Bool{near(a.x,b.x) && near(a.y,b.y)}
    static func center(_ frame:CGRect)->CGPoint{CGPoint(x:frame.midX,y:frame.midY)}
    static func inside(_ frame:CGRect,_ area:CGRect)->Bool{
        frame.minX>=area.minX-0.001 && frame.maxX<=area.maxX+0.001 && frame.minY>=area.minY-0.001 && frame.maxY<=area.maxY+0.001
    }
    static func geometry(){
        let visible=CGRect(x:-1920,y:-1080,width:1920,height:1040)
        let probes:[(CGPoint,Int)]=[
            (CGPoint(x:-1890,y:-520),0),(CGPoint(x:-30,y:-520),1),
            (CGPoint(x:-940,y:-1050),2),(CGPoint(x:-940,y:-70),3)
        ]
        for size:CGFloat in [32,48,96] {
            for (point,edge) in probes {
                let frame=OrbLayout.frame(center:point,size:size,within:visible,snap:true)
                expect(near(frame.width,size) && near(frame.height,size),"Docking must preserve the selected size")
                expect(inside(frame,visible),"Negative-origin display docking must stay in bounds")
                switch edge {
                case 0:expect(near(frame.minX,-1910),"Left docking must respect the work-area margin")
                case 1:expect(near(frame.maxX,-10),"Right docking must respect the work-area margin")
                case 2:expect(near(frame.minY,-1070),"Bottom docking must respect the work-area margin")
                default:expect(near(frame.maxY,-50),"Top docking must respect the work-area margin")
                }
            }
            let point=CGPoint(x:-1300,y:-730)
            let free=OrbLayout.frame(center:point,size:size,within:visible,snap:false)
            expect(same(center(free),point),"Free positioning must preserve an off-center interior position")
            for outside in [CGPoint(x:-4000,y:-4000),CGPoint(x:4000,y:4000)] {
                let clamped=OrbLayout.frame(center:outside,size:size,within:visible,snap:false)
                expect(inside(clamped,visible.insetBy(dx:10,dy:10)),"Free positioning must clamp unreachable positions")
            }
            let saved=OrbLayout.normalizedCenter(of:free,in:visible)
            let restored=OrbLayout.restoredFrame(size:size,within:visible,normalized:saved,snap:false)
            expect(same(center(restored),point),"Free position must survive a save/restore round trip")
            let resized=CGRect(x:500,y:200,width:960,height:520)
            let adapted=OrbLayout.restoredFrame(size:size,within:resized,normalized:saved,snap:false)
            expect(same(center(adapted),CGPoint(x:810,y:375)),"Resolution changes must preserve relative position rather than old absolute coordinates")
            let back=OrbLayout.restoredFrame(size:size,within:visible,normalized:OrbLayout.normalizedCenter(of:adapted,in:resized),snap:false)
            expect(same(center(back),point),"Changing display geometry and returning must retain position")
        }
        let tiny=CGRect(x:-40,y:80,width:19,height:15)
        for size:CGFloat in [32,48,96] {
            for snap in [false,true] {
                let frame=OrbLayout.frame(center:CGPoint(x:200,y:-300),size:size,within:tiny,snap:snap)
                expect(frame.width==15 && frame.height==15 && inside(frame,tiny),"Tiny work areas must shrink the orb safely without inverted bounds")
            }
        }
        let regular=CGRect(x:0,y:0,width:1200,height:800)
        let invalid=OrbLayout.restoredFrame(size:48,within:regular,normalized:CGPoint(x:CGFloat.nan,y:CGFloat.infinity),snap:false)
        expect(same(center(invalid),CGPoint(x:600,y:400)),"Nonfinite stored positions must fall back to the work-area center")
        let outOfRange=OrbLayout.restoredFrame(size:48,within:regular,normalized:CGPoint(x:-8,y:12),snap:false)
        expect(near(outOfRange.minX,10) && near(outOfRange.maxY,790),"Out-of-range stored positions must recover inside the work area")
        print("PASS orb layout: \(checks) checks; four edges, negative origins, free placement, size limits, tiny work areas and resolution changes")
    }
    static func gestures(){
        let begin=checks
        var click=OrbDragGesture(start:CGPoint(x:10,y:20),origin:CGPoint(x:-40,y:80),locked:false)
        expect(click.move(to:CGPoint(x:14,y:20))==nil && click.shouldCapture,"Pointer movement within the threshold remains a click")
        let moved=click.move(to:CGPoint(x:15,y:23))
        expect(moved.map{same($0,CGPoint(x:-35,y:83))} == true && click.dragged && !click.shouldCapture,"A real drag moves relative to the original window position and suppresses capture")
        _ = click.move(to:CGPoint(x:10,y:20))
        expect(!click.shouldCapture,"Dragging back to the start must not accidentally capture")
        var lockedClick=OrbDragGesture(start:CGPoint(x:10,y:20),origin:.zero,locked:true)
        expect(lockedClick.move(to:CGPoint(x:11,y:22))==nil && lockedClick.shouldCapture,"A locked orb must still support a deliberate click")
        var lockedDrag=OrbDragGesture(start:CGPoint(x:10,y:20),origin:.zero,locked:true)
        expect(lockedDrag.move(to:CGPoint(x:80,y:90))==nil && lockedDrag.dragged && !lockedDrag.shouldCapture,"Dragging a locked orb must neither move it nor trigger a screenshot")
        expect(lockedDrag.move(to:CGPoint(x:10,y:20))==nil && !lockedDrag.shouldCapture,"Returning a locked drag to its starting point must remain suppressed")
        print("PASS orb gestures: \(checks-begin) checks; drag threshold, locked clicks, locked drags and accidental-capture prevention")
    }
    static func preferences(_ defaults:UserDefaults){
        let begin=checks,p=Preferences(defaults:defaults)
        expect(p.orbSnapToEdge,"Existing installations must retain edge docking by default")
        expect(p.orbSize==48 && !p.orbPositionLocked,"Existing installations must retain the 48-point unlocked orb")
        p.orbSnapToEdge=false;p.orbSize=72;p.orbPositionLocked=true
        let reopened=Preferences(defaults:defaults)
        expect(!reopened.orbSnapToEdge && reopened.orbSize==72 && reopened.orbPositionLocked,"Explicit free placement, size and lock must persist together")
        p.orbPositionLocked=false
        expect(!Preferences(defaults:defaults).orbPositionLocked,"Explicit unlocked preference must persist")
        p.orbSize=5;expect(p.orbSize==32,"Too-small requested sizes must clamp to 32 points")
        p.orbSize=999;expect(p.orbSize==96,"Too-large requested sizes must clamp to 96 points")
        p.orbSize = .nan;expect(p.orbSize==48,"Invalid requested size must fall back to 48 points")
        for invalid in [Double.nan,Double.infinity,-Double.infinity] {
            defaults.set(invalid,forKey:"orbSize")
            expect(reopened.orbSize==48,"Invalid legacy size must recover even when read directly from defaults")
        }
        defaults.set(-3,forKey:"orbSize");expect(reopened.orbSize==32,"Legacy stored undersize must clamp")
        defaults.set(150,forKey:"orbSize");expect(reopened.orbSize==96,"Legacy stored oversize must clamp")
        print("PASS orb preferences: \(checks-begin) checks; migration defaults, explicit opt-outs, persistence and invalid-size recovery")
    }
    @MainActor static func material(_ controller:OrbController,size:CGFloat){
        controller.view.layoutSubtreeIfNeeded()
        expect(near(controller.panel.frame.width,size) && near(controller.view.bounds.width,size) && near(controller.view.bounds.height,size),"Native panel and input surface must resize together")
        let materials=controller.view.subviews.compactMap{$0 as? MaterialSurface}
        expect(materials.count==1,"Changing size must replace the material without accumulating glass layers")
        guard let surface=materials.first else{return}
        expect(surface.frame==controller.view.bounds,"The material must fill the resized input surface")
        expect(surface.subviews.contains{near($0.layer?.cornerRadius ?? -1,size/2)},"The actual native material must remain circular at the chosen size")
        let symbol=controller.view.subviews.compactMap{$0 as? BrandView}.first
        expect(symbol?.frame==controller.view.bounds.insetBy(dx:size/6,dy:size/6),"Brand symbol must scale with the container and keep its clear space")
        expect(controller.view.decorations.frame==controller.view.bounds,"Hover and recording decorations must follow the resized circle")
    }
    @MainActor static func nativeWindows(_ defaults:UserDefaults){
        let begin=checks,p=Preferences(defaults:defaults)
        guard let screen=NSScreen.main else{preconditionFailure("Native orb checks require a logged-in macOS display session")}
        let area=screen.visibleFrame
        p.orbHidden=true;p.orbSnapToEdge=false;p.orbSize=48;p.orbPositionLocked=false
        defaults.set("left",forKey:"orbEdge");defaults.set(0.7,forKey:"orbFraction")
        let migrated=OrbController(preferences:p)
        let expectedY=area.minY+10+(area.height-20-48)*0.7
        // NSWindow aligns its origin to integral logical points even on Retina displays.
        expect(abs(migrated.panel.frame.minX-area.minX-10)<=1 && abs(migrated.panel.frame.minY-expectedY)<=1,"Legacy edge and vertical fraction must migrate within native window alignment precision")
        expect(defaults.object(forKey:"orbNormalizedX") != nil && defaults.object(forKey:"orbNormalizedY") != nil,"Legacy position must be saved in the new relative-position format")
        expect(!migrated.panel.isVisible,"Migrating a hidden orb must not display it")
        let point=CGPoint(x:floor(area.minX+area.width*0.44),y:floor(area.minY+area.height*0.57))
        migrated.panel.setFrameOrigin(CGPoint(x:point.x-24,y:point.y-24));migrated.dockAndSave()
        expect(same(center(migrated.panel.frame),point),"Dragging with snapping off must preserve an interior location")
        material(migrated,size:48)
        p.orbSize=96;migrated.applyPreferences()
        expect(same(center(migrated.panel.frame),point),"Resizing an unlocked free orb must preserve its center")
        material(migrated,size:96)
        expect(!migrated.panel.isVisible && p.orbHidden,"Applying appearance changes must retain the hidden state")
        let recreated=OrbController(preferences:Preferences(defaults:defaults))
        expect(same(center(recreated.panel.frame),point) && near(recreated.panel.frame.width,96),"Recreating the native controller must restore free position and size")
        p.orbPositionLocked=true;p.orbSnapToEdge=true;p.orbSize=48;migrated.applyPreferences()
        expect(same(center(migrated.panel.frame),point) && migrated.view.positionLocked,"Locking position must take priority over snapping when resizing")
        material(migrated,size:48)
        expect(migrated.view.context?.items.first(where:{$0.title=="锁定当前位置"})?.state == .on,"Context menu lock state must match the active setting")
        var notifications=0;migrated.onStateChanged={notifications+=1};migrated.toggleLock()
        expect(!p.orbPositionLocked && !migrated.view.positionLocked && notifications==1,"Context-menu unlock must update preferences, native gesture state and the settings callback")
        expect(!migrated.panel.isVisible,"Unlocking a hidden orb must not restore it unexpectedly")
        expect(same(center(migrated.panel.frame),point),"Unlocking after enabling snap while locked must preserve the chosen location")
        migrated.restorePosition()
        expect(same(center(migrated.panel.frame),point),"Restoring must not snap a free position that was unlocked after changing snap while locked")
        let unlockedRecreated=OrbController(preferences:Preferences(defaults:defaults))
        expect(same(center(unlockedRecreated.panel.frame),point) && !unlockedRecreated.view.positionLocked,"Recreating after unlock must retain the free position until the next actual drag or snap change")
        p.orbSnapToEdge=false;migrated.applyPreferences();p.orbSnapToEdge=true;migrated.applyPreferences()
        let f=migrated.panel.frame
        expect(near(f.minX,area.minX+10) || near(f.maxX,area.maxX-10) || near(f.minY,area.minY+10) || near(f.maxY,area.maxY-10),"Enabling snap must move an unlocked interior orb to a real work-area edge")
        p.orbPositionLocked=true;migrated.applyPreferences();let before=migrated.panel.frame;migrated.revalidate()
        expect(same(center(migrated.panel.frame),center(before)) && migrated.view.positionLocked && !migrated.panel.isVisible,"Display/wake revalidation must retain locked placement and hidden state")
        migrated.panel.close();recreated.panel.close();unlockedRecreated.panel.close()
        print("PASS native orb: \(checks-begin) checks; hidden NSPanel resizing, actual circular material, lock state, migration, free-position restoration and revalidation")
    }
    @MainActor static func main(){
        _ = NSApplication.shared
        let suite="Snapliq.OrbPreferencesTests."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer{defaults.removePersistentDomain(forName:suite)}
        geometry();gestures();preferences(defaults)
        defaults.removePersistentDomain(forName:suite)
        nativeWindows(defaults)
        print("PASS orb customization: \(checks) checks; isolated defaults, hidden windows, no screenshot, no microphone and no global input")
    }
}
