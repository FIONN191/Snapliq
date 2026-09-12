import AppKit
let url=URL(fileURLWithPath:CommandLine.arguments[2]);let pb=NSPasteboard.general
if CommandLine.arguments[1]=="backup" {
 let items=pb.pasteboardItems?.map{ item in Dictionary(uniqueKeysWithValues:item.types.compactMap{ t -> (String,Data)? in guard let d=item.data(forType:t) else{return nil};return (t.rawValue,d)})} ?? []
 try PropertyListEncoder().encode(items).write(to:url)
} else {
 let items=try PropertyListDecoder().decode([[String:Data]].self,from:Data(contentsOf:url));pb.clearContents()
 let result=items.map{ values -> NSPasteboardItem in let i=NSPasteboardItem();for (t,d) in values{i.setData(d,forType:.init(t))};return i}
 if !result.isEmpty{pb.writeObjects(result)};try FileManager.default.removeItem(at:url)
}
