import AppKit
guard let data=NSPasteboard.general.data(forType:.png),let bitmap=NSBitmapImageRep(data:data) else{print("NO_IMAGE");exit(1)}
let pixel=bitmap.colorAt(x:bitmap.pixelsWide/2,y:bitmap.pixelsHigh/2)!.usingColorSpace(.sRGB)!
let result:[String:Any]=["width":bitmap.pixelsWide,"height":bitmap.pixelsHigh,"red":pixel.redComponent,"green":pixel.greenComponent,"blue":pixel.blueComponent]
if CommandLine.arguments.count>1{try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))}
print(String(data:try JSONSerialization.data(withJSONObject:result,options:.sortedKeys),encoding:.utf8)!)
