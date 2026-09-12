import AppKit
import ApplicationServices
struct DesktopWindowTarget {
    let frame:CGRect
    let pid:pid_t
}
/// State is confined to the main thread; only the bounded AX resolver runs on the worker queue.
final class SmartSelection {
    typealias Resolver=(DesktopWindowTarget,CGPoint,CGFloat)->CGRect?
    private struct Pending {
        let target:DesktopWindowTarget
        let point:CGPoint
        let top:CGFloat
        let completion:(CGRect?)->Void
    }
    private let targets:[DesktopWindowTarget]
    private let controlsEnabled:()->Bool
    private let pointerLocation:()->CGPoint
    private let resolver:Resolver
    private let queue=DispatchQueue(label:"Snapliq.AccessibilityHitTest",qos:.userInitiated)
    private var lastRequest=0.0
    private var busy=false
    private var valid=true
    private var pending:Pending?
    private var scheduled:DispatchWorkItem?
    private var cached:(pid:pid_t,window:CGRect,frame:CGRect,time:Double)?
    private var delivered=false
    private var lastFrame:CGRect?
    init(targets:[DesktopWindowTarget],
         controlsEnabled:@escaping()->Bool={Preferences.shared.defaults.bool(forKey:"smartControls") && AXIsProcessTrusted()},
         pointerLocation:@escaping()->CGPoint={NSEvent.mouseLocation},
         resolver:@escaping Resolver=SmartSelection.resolve) {
        self.targets=targets.filter{$0.pid != getpid()}
        self.controlsEnabled=controlsEnabled;self.pointerLocation=pointerLocation;self.resolver=resolver
    }
    func cancel(){valid=false;pending=nil;scheduled?.cancel();scheduled=nil;cached=nil}
    private func emit(_ frame:CGRect?,to completion:(CGRect?)->Void) {
        guard !delivered || lastFrame != frame else{return}
        delivered=true;lastFrame=frame;completion(frame)
    }
    func hit(_ point:CGPoint,completion:@escaping(CGRect?)->Void){
        guard valid else{return}
        guard let target=targets.first(where:{$0.frame.contains(point)}) else {
            pending=nil;emit(nil,to:completion);return
        }
        guard controlsEnabled() else {
            pending=nil;cached=nil;emit(target.frame,to:completion);return
        }
        if let cached=cached,cached.pid==target.pid,cached.window==target.frame,
           cached.frame.contains(point),now()-cached.time<0.3 {
            pending=nil;emit(cached.frame,to:completion);return
        }
        emit(target.frame,to:completion)
        pending=Pending(target:target,point:point,top:NSScreen.screens.first?.frame.maxY ?? 0,completion:completion)
        drain()
    }
    private func drain() {
        guard valid,!busy,pending != nil else{return}
        let delay=max(0,0.10-(now()-lastRequest))
        if delay>0 {
            guard scheduled==nil else{return}
            let work=DispatchWorkItem{[weak self] in self?.scheduled=nil;self?.drain()}
            scheduled=work;DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:work);return
        }
        scheduled?.cancel();scheduled=nil
        guard let task=pending else{return};pending=nil;busy=true;lastRequest=now()
        let resolve=resolver
        queue.async{[weak self] in
            let frame=resolve(task.target,task.point,task.top)
            DispatchQueue.main.async{[weak self] in
                guard let self=self else{return};self.busy=false
                guard self.valid else{return}
                let pointer=self.pointerLocation()
                if self.pending==nil,self.controlsEnabled(),
                   hypot(pointer.x-task.point.x,pointer.y-task.point.y)<5 {
                    if let frame=frame,frame != task.target.frame {
                        self.cached=(task.target.pid,task.target.frame,frame,now())
                    }
                    self.emit(frame ?? task.target.frame,to:task.completion)
                }
                // Process the most recent pointer position even if no new mouse event arrives.
                self.drain()
            }
        }
    }
    private static func resolve(_ target:DesktopWindowTarget,_ point:CGPoint,_ top:CGFloat)->CGRect? {
        let app=AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(app,0.05)
        var result:AXUIElement?
        guard AXUIElementCopyElementAtPosition(app,Float(point.x),Float(top-point.y),&result) == .success,
              let element=result else{return nil}
        var position:CFTypeRef?,size:CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,kAXPositionAttribute as CFString,&position) == .success,
              AXUIElementCopyAttributeValue(element,kAXSizeAttribute as CFString,&size) == .success,
              let position=position,let size=size,
              CFGetTypeID(position)==AXValueGetTypeID(),CFGetTypeID(size)==AXValueGetTypeID() else{return nil}
        var p=CGPoint.zero,s=CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position,to:AXValue.self),.cgPoint,&p),
              AXValueGetValue(unsafeBitCast(size,to:AXValue.self),.cgSize,&s) else{return nil}
        let r=CGRect(x:p.x,y:top-p.y-s.height,width:s.width,height:s.height).intersection(target.frame)
        return r.width>3 && r.height>3 && r.contains(point) ? r:nil
    }
}
