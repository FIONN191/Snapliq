import AppKit
import Darwin
enum NativeTransport {
 static let limit=65536
 static func readFrame(_ fd:Int32)->Data?{
  func take(_ count:Int)->Data?{var data=Data(count:count);let ok=data.withUnsafeMutableBytes{b -> Bool in var readCount=0;while readCount<count{let n=Darwin.read(fd,b.baseAddress!.advanced(by:readCount),count-readCount);if n<=0{return false};readCount+=n};return true};return ok ? data:nil}
  guard let header=take(4) else{return nil};let size=header.withUnsafeBytes{Int(UInt32(littleEndian:$0.loadUnaligned(as:UInt32.self)))};guard size>0,size<=limit else{return nil};return take(size)
 }
 static func send(_ data:Data,to fd:Int32){var length=UInt32(data.count).littleEndian;var bytes=Data(bytes:&length,count:4);bytes.append(data);bytes.withUnsafeBytes{b in var sent=0;while sent<b.count{let n=Darwin.write(fd,b.baseAddress!.advanced(by:sent),b.count-sent);if n<=0{break};sent+=n}}}
 static func connectDesktop()->Int32?{
  let path=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent((info["SnapliqDataDirectory"] as? String ?? "Snapliq Development")+"/bridge.sock").path
  guard path.utf8.count<104 else{return nil};let fd=socket(AF_UNIX,SOCK_STREAM,0);guard fd>=0 else{return nil}
  var timeout=timeval(tv_sec:3,tv_usec:0);setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size));setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
  var noSignal:Int32=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noSignal,socklen_t(MemoryLayout<Int32>.size))
  var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX)
  withUnsafeMutablePointer(to:&address.sun_path){$0.withMemoryRebound(to:CChar.self,capacity:104){_ = strcpy($0,path)}}
  let result=withUnsafePointer(to:&address){$0.withMemoryRebound(to:sockaddr.self,capacity:1){connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
  if result==0{return fd};close(fd);return nil
 }
}
let origin=CommandLine.arguments.dropFirst().first ?? ""
let executable=URL(fileURLWithPath:CommandLine.arguments[0]).resolvingSymlinksInPath()
let app=executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let info=NSDictionary(contentsOf:app.appendingPathComponent("Contents/Info.plist")) ?? [:]
let expected="chrome-extension://"+(info["SnapliqChromeExtensionID"] as? String ?? "")+"/"
guard origin==expected,origin.count>25 else{exit(2)}
while let data=NativeTransport.readFrame(STDIN_FILENO) {
 guard let message=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let action=message["action"] as? String,["ping","capture","record","settings"].contains(action) else {
  NativeTransport.send(Data("{\"ok\":false,\"error\":\"invalid_request\"}".utf8),to:STDOUT_FILENO);continue
 }
 var fd=NativeTransport.connectDesktop()
 if fd==nil,action != "ping" {
  let config=NSWorkspace.OpenConfiguration();config.activates=false
  NSWorkspace.shared.openApplication(at:app,configuration:config){_,_ in}
  for _ in 0..<50 {RunLoop.current.run(until:Date().addingTimeInterval(0.1));fd=NativeTransport.connectDesktop();if fd != nil{break}}
 }
 if let socket=fd {
  NativeTransport.send(data,to:socket)
  if let reply=NativeTransport.readFrame(socket){NativeTransport.send(reply,to:STDOUT_FILENO)}
  else{NativeTransport.send(Data("{\"ok\":false,\"error\":\"desktop_timeout\"}".utf8),to:STDOUT_FILENO)}
  close(socket)
 }else{NativeTransport.send(Data("{\"ok\":false,\"error\":\"desktop_not_running\"}".utf8),to:STDOUT_FILENO)}
}
