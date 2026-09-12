import AppKit
final class QueryProbe {
 let lock=NSLock();var count=0,active=0,maximum=0
 func begin(){lock.lock();count+=1;active+=1;maximum=max(maximum,active);lock.unlock()}
 func end(){lock.lock();active-=1;lock.unlock()}
 func snapshot()->(Int,Int){lock.lock();defer{lock.unlock()};return(count,maximum)}
}
@main struct SmartSelectionTests {
 @MainActor static func main() async {
  _ = NSApplication.shared
  let window=CGRect(x:0,y:0,width:400,height:300)
  let left=CGRect(x:10,y:10,width:80,height:40),right=CGRect(x:210,y:10,width:80,height:40)
  let target=DesktopWindowTarget(frame:window,pid:getpid()+1000),probe=QueryProbe()
  var pointer=CGPoint(x:30,y:30),results=[CGRect?]()
  let smart=SmartSelection(targets:[target],controlsEnabled:{true},pointerLocation:{pointer},resolver:{_,point,_ in
   probe.begin();Thread.sleep(forTimeInterval:0.18);probe.end();return point.x<100 ? left:right
  })
  smart.hit(pointer){results.append($0)}
  try? await Task.sleep(nanoseconds:30_000_000)
  pointer=CGPoint(x:230,y:30)
  smart.hit(pointer){results.append($0)}
  for _ in 0..<100{if results.last! == right{break};try? await Task.sleep(nanoseconds:10_000_000)}
  precondition(results.last! == right,"Latest stationary pointer never resolved")
  precondition(!results.contains{$0==left},"Stale result escaped")
  precondition(probe.snapshot().1==1,"Concurrent queries exceeded one")
  let queries=probe.snapshot().0,delivered=results.count
  for _ in 0..<10{smart.hit(pointer){results.append($0)}}
  precondition(probe.snapshot().0==queries && results.count==delivered,"Cache or candidate deduplication failed")
  smart.cancel()
  print("PASS newest pointer coalesced; stale result discarded; one query in flight; cache and boundary deduplication")

  var cancelledResults=[CGRect?]()
  let cancelled=SmartSelection(targets:[target],controlsEnabled:{true},pointerLocation:{pointer},resolver:{_,_,_ in Thread.sleep(forTimeInterval:0.1);return right})
  cancelled.hit(pointer){cancelledResults.append($0)};cancelled.cancel()
  try? await Task.sleep(nanoseconds:200_000_000)
  precondition(cancelledResults.count==1,"Cancelled query delivered late result")
  let denied=SmartSelection(targets:[target],controlsEnabled:{false},resolver:{_,_,_ in preconditionFailure("AX called without permission")})
  denied.hit(pointer){precondition($0==window)}
  let own=SmartSelection(targets:[DesktopWindowTarget(frame:window,pid:getpid())],controlsEnabled:{true},resolver:{_,_,_ in preconditionFailure("Own overlay queried")})
  own.hit(pointer){precondition($0==nil)}
  print("PASS cancellation, permission fallback and own-process exclusion")

  let front=CGRect(x:0,y:0,width:100,height:100),back=CGRect(x:50,y:0,width:150,height:100)
  pointer=CGPoint(x:150,y:30);var result:CGRect?
  let windows=SmartSelection(targets:[DesktopWindowTarget(frame:front,pid:target.pid),DesktopWindowTarget(frame:back,pid:target.pid)],controlsEnabled:{true},pointerLocation:{pointer},resolver:{t,_,_ in t.frame==front ? CGRect(x:60,y:10,width:30,height:50):CGRect(x:50,y:10,width:130,height:50)})
  windows.hit(pointer){result=$0}
  try? await Task.sleep(nanoseconds:60_000_000)
  pointer=CGPoint(x:75,y:30);windows.hit(pointer){result=$0}
  try? await Task.sleep(nanoseconds:160_000_000)
  precondition(result==CGRect(x:60,y:10,width:30,height:50),"Cached control leaked across same-app windows")
  windows.cancel()
  print("PASS cache is scoped to window boundaries as well as process")
 }
}
