import AppKit
@main struct RecordingRegionTests {
 static func main()throws{
  func crop(_ r:CGRect,_ f:CGRect,_ s:CGFloat)throws->RecordingRegion{try .init(selection:r,displayID:1,displayFrame:f,scale:s)}
  func reject(_ body:()throws->Void){do{try body();fatalError("Expected rejection")}catch{}}
  let screen=CGRect(x:-1440,y:-200,width:1440,height:900)
  let r=try crop(.init(x:-1340,y:400,width:301,height:101),screen,2)
  precondition(r.sourceRect==CGRect(x:100,y:199,width:301,height:101))
  precondition(r.pixelWidth==602 && r.pixelHeight==202)
  let one=try crop(.init(x:-1340,y:400,width:301,height:101),screen,1)
  precondition(one.pixelWidth==300 && one.pixelHeight==100)
  let fraction=try crop(.init(x:-1339.7,y:400.3,width:300.1,height:100.1),screen,1.5)
  precondition(fraction.sourceRect.minX>=100.3 && fraction.pixelWidth%2==0 && fraction.pixelHeight%2==0)
  precondition(fraction.sourceRect.maxX<=400.4+0.0001)
  try r.validate(frame:screen,pointPixelScale:2)
  reject{try r.validate(frame:screen.offsetBy(dx:1,dy:0),pointPixelScale:2)}
  reject{try r.validate(frame:screen,pointPixelScale:1)}
  reject{_ = try crop(.init(x:-10,y:10,width:20,height:20),screen,2)}
  reject{_ = try crop(.init(x:-100,y:0,width:0.2,height:20),screen,2)}
  reject{_ = try crop(.init(x:-100,y:0,width:20,height:20),screen,.infinity)}
  reject{_ = try crop(.init(x:-100,y:0,width:20,height:20),screen,0)}
  reject{_ = try RecordingRegion.resolve(.init(x:0,y:0,width:20,height:20),snapshots:[])}
  for scale:CGFloat in [1,1.25,1.5,2,3] {
   for x in 0..<150 {
    let selection=CGRect(x:screen.minX+CGFloat(x)+0.2,y:screen.minY+50.4,width:201.2,height:157.7)
    let c=try crop(selection,screen,scale)
    precondition(c.pixelWidth%2==0 && c.pixelHeight%2==0)
    let original=CGRect(x:selection.minX-screen.minX,y:screen.maxY-selection.maxY,width:selection.width,height:selection.height)
    precondition(original.insetBy(dx:-0.0001,dy:-0.0001).contains(c.sourceRect))
    precondition(original.width*scale-CGFloat(c.pixelWidth)<3.01)
   }
  }
  print("PASS region geometry: 750 fractional/negative-coordinate cases; Retina, inward even-pixel alignment, tiny/cross-display rejection and topology invalidation")
 }
}
