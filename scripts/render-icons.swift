import AppKit
import Foundation
let output=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
func mark(_ rect:CGRect,_ color:NSColor,_ optical:Bool=false){
 NSGraphicsContext.saveGraphicsState()
 NSGraphicsContext.current!.cgContext.translateBy(x:rect.minX,y:rect.minY)
 let factor=rect.width/64;NSGraphicsContext.current!.cgContext.scaleBy(x:factor,y:factor)
 color.setStroke();color.setFill()
 let p=NSBezierPath();p.lineWidth=optical ? 7.2:6.5;p.lineCapStyle = .round;p.lineJoinStyle = .round
 p.move(to:.init(x:14,y:30));p.line(to:.init(x:14,y:50));p.line(to:.init(x:34,y:50))
 p.move(to:.init(x:30,y:14));p.line(to:.init(x:50,y:14));p.line(to:.init(x:50,y:34));p.stroke()
 let d:CGFloat=optical ? 8.2:7.2;NSBezierPath(ovalIn:.init(x:32-d/2,y:32-d/2,width:d,height:d)).fill()
 NSGraphicsContext.restoreGraphicsState()
}
func render(_ size:Int,_ style:String)->NSBitmapImageRep {
 let b=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 b.size=NSSize(width:size,height:size);NSGraphicsContext.saveGraphicsState()
 NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:b)
 let r=CGRect(x:0,y:0,width:size,height:size)
 if style=="dark" || style=="light" {
  let light=style=="light",inset=CGFloat(size)*0.055
  let shell=NSBezierPath(roundedRect:r.insetBy(dx:inset,dy:inset),xRadius:CGFloat(size)*0.2,yRadius:CGFloat(size)*0.2)
  let c1=light ? NSColor(white:0.98,alpha:1):NSColor(white:0.24,alpha:1)
  let c2=light ? NSColor(white:0.79,alpha:1):NSColor(white:0.055,alpha:1)
  NSGradient(starting:c1,ending:c2)!.draw(in:shell,angle:270)
  NSColor(white:light ? 1:0.6,alpha:0.6).setStroke();shell.lineWidth=max(1,CGFloat(size)*0.002);shell.stroke()
  let frame=r.insetBy(dx:CGFloat(size)*0.14,dy:CGFloat(size)*0.14)
  NSGraphicsContext.saveGraphicsState()
  let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(light ? 0.12:0.55);shadow.shadowOffset = .init(width:0,height:-CGFloat(size)*0.016);shadow.shadowBlurRadius=CGFloat(size)*0.018;shadow.set()
  mark(frame,light ? NSColor(white:0.14,alpha:1):NSColor(white:0.9,alpha:1),size<=32)
  NSGraphicsContext.restoreGraphicsState()
  // A restrained edge highlight, kept separate from the editable geometric source.
  if size>=64 {mark(frame.offsetBy(dx:0,dy:CGFloat(size)*0.0015),light ? NSColor(white:0.15,alpha:0.3):NSColor(white:1,alpha:0.16))}
 } else if style=="orb"{
  let circle=NSBezierPath(ovalIn:r.insetBy(dx:1,dy:1));NSGradient(starting:NSColor(white:0.4,alpha:0.85),ending:NSColor(white:0.1,alpha:0.9))!.draw(in:circle,angle:270)
  NSColor.white.withAlphaComponent(0.4).setStroke();circle.lineWidth=1;circle.stroke()
  mark(r.insetBy(dx:CGFloat(size)*0.16,dy:CGFloat(size)*0.16),.white,size<=32)
 }else{mark(r,style=="white" ? .white:.black,size<=32)}
 NSGraphicsContext.restoreGraphicsState();return b
}
for style in ["dark","light","black","white","orb"] {
 for size in [16,18,20,24,32,36,40,48,64,96,128,256,512,1024] {
  try render(size,style).representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("\(style)-\(size).png"))
 }
}
let sheet=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1100,pixelsHigh:500,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:sheet)
NSColor(white:0.94,alpha:1).setFill();NSBezierPath(rect:.init(x:0,y:0,width:550,height:500)).fill()
NSColor(white:0.08,alpha:1).setFill();NSBezierPath(rect:.init(x:550,y:0,width:550,height:500)).fill()
for side in 0..<2 {
 let color:NSColor=side==0 ? .black:.white
 for (i,size) in [16,24,32,64].enumerated() {
  let x=CGFloat(side*550+40+i*125)
  NSImage(cgImage:render(size,side==0 ? "black":"white").cgImage!,size:NSSize(width:size,height:size)).draw(in:.init(x:x,y:365,width:CGFloat(size),height:CGFloat(size)))
  ("\(size) px" as NSString).draw(at:.init(x:x,y:335),withAttributes:[.font:NSFont.systemFont(ofSize:13),.foregroundColor:color])
 }
 NSImage(cgImage:render(256,side==0 ? "light":"dark").cgImage!,size:NSSize(width:230,height:230)).draw(in:.init(x:CGFloat(side*550+30),y:60,width:230,height:230))
 NSImage(cgImage:render(128,"orb").cgImage!,size:NSSize(width:100,height:100)).draw(in:.init(x:CGFloat(side*550+335),y:150,width:100,height:100))
}
try sheet.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("brand-contact-sheet.png"))
print("Rendered platform PNGs and contact sheet")
