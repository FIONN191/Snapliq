import AppKit
import Darwin

/// A local, user-only command transport. It does not own or keep the application alive.
final class DesktopBridge {
    private var listener:Int32 = -1
    private let path:String
    init(path:String=DesktopBridge.socketPath){self.path=path}
    private let queue=DispatchQueue(label:"Snapliq.NativeBridge",qos:.utility)
    var onAction:((String)->Void)?
    static let maxMessage=65536
    static var socketPath:String {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent(Product.dataDirectory+"/bridge.sock").path
    }
    func start(){
        let path=self.path
        guard path.utf8.count<104 else{Metrics.shared.write("bridge_unavailable",["reason":"socket_path_too_long"]);return}
        let directory=URL(fileURLWithPath:path).deletingLastPathComponent()
        do{try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)}catch{return}
        let fd=socket(AF_UNIX,SOCK_STREAM,0);guard fd>=0 else{return}
        // Single desktop instance has already been enforced before binding.
        unlink(path)
        var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to:&address.sun_path){ptr in ptr.withMemoryRebound(to:CChar.self,capacity:104){_ = strcpy($0,path)}}
        let bound=withUnsafePointer(to:&address){$0.withMemoryRebound(to:sockaddr.self,capacity:1){bind(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
        guard bound==0,listen(fd,4)==0 else{close(fd);return}
        chmod(path,0o600);listener=fd
        let callback=onAction
        queue.async{
            while true {
                let client=accept(fd,nil,nil);if client<0{break}
                var timeout=timeval(tv_sec:2,tv_usec:0)
                setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
                setsockopt(client,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
                var noSignal:Int32=1;setsockopt(client,SOL_SOCKET,SO_NOSIGPIPE,&noSignal,socklen_t(MemoryLayout<Int32>.size))
                var uid:uid_t=0,gid:gid_t=0
                if getpeereid(client,&uid,&gid)==0,uid==getuid(),let data=Self.readFrame(client),
                   let message=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
                   let action=message["action"] as? String,["ping","capture","record","settings"].contains(action) {
                    let reply:[String:Any]=["ok":true,"accepted":action != "ping","version":Product.version,"capabilities":["capture","record","settings"],"requestId":String((message["requestId"] as? String ?? "").prefix(128))]
                    Self.writeFrame(client,try! JSONSerialization.data(withJSONObject:reply))
                    if action != "ping"{DispatchQueue.main.async{callback?(action)}}
                } else{Self.writeFrame(client,Data("{\"ok\":false,\"error\":\"invalid_request\"}".utf8))}
                close(client)
            }
        }
    }
    func stop(){if listener>=0{shutdown(listener,SHUT_RDWR);close(listener);listener = -1;unlink(path)}}
    deinit{stop()}
    static func readFrame(_ fd:Int32)->Data?{
        func readBytes(_ count:Int)->Data?{
            var data=Data(count:count);var total=0
            let ok=data.withUnsafeMutableBytes{buffer -> Bool in
                while total<count{let n=Darwin.read(fd,buffer.baseAddress!.advanced(by:total),count-total);if n<=0{return false};total+=n};return true
            };return ok ? data:nil
        }
        guard let header=readBytes(4) else{return nil}
        let count=header.withUnsafeBytes{Int(UInt32(littleEndian:$0.loadUnaligned(as:UInt32.self)))}
        guard count>0,count<=maxMessage else{return nil};return readBytes(count)
    }
    static func writeFrame(_ fd:Int32,_ data:Data){
        guard data.count<=maxMessage else{return}
        var length=UInt32(data.count).littleEndian;var frame=Data(bytes:&length,count:4);frame.append(data)
        frame.withUnsafeBytes{buffer in var sent=0;while sent<buffer.count{let n=Darwin.write(fd,buffer.baseAddress!.advanced(by:sent),buffer.count-sent);if n<=0{break};sent+=n}}
    }
    static func registerChromeHost()throws->URL {
        guard let id=Product.info["SnapliqChromeExtensionID"] as? String,!id.isEmpty else{throw CaptureFailure.message("扩展标识未配置。")}
        let host=Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/SnapliqBridge")
        guard FileManager.default.isExecutableFile(atPath:host.path) else{throw CaptureFailure.message("应用内浏览器通信模块缺失。")}
        let folder=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let path=folder.appendingPathComponent("com.snapliq.desktop.development.json")
        let manifest:[String:Any]=["name":"com.snapliq.desktop.development","description":"Snapliq desktop request adapter","path":host.path,"type":"stdio","allowed_origins":["chrome-extension://"+id+"/"]]
        try JSONSerialization.data(withJSONObject:manifest,options:.prettyPrinted).write(to:path,options:.atomic)
        return path
    }
}
