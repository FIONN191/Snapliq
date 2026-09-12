import AppKit
import Vision

enum LocalOCR {
    static func recognize(_ image:CGImage)throws->String {
        let request=VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection=true
        let available=try request.supportedRecognitionLanguages()
        request.recognitionLanguages=["zh-Hans","zh-Hant","en-US"].filter{available.contains($0)}
        try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
        return (request.results ?? []).compactMap{$0.topCandidates(1).first?.string}.joined(separator:"\n")
    }
}
final class OCRPanel:NSWindowController,NSWindowDelegate {
    private let textView=NSTextView()
    private let status=NSTextField(labelWithString:"正在本机识别中文和英文…")
    private var generation=0
    var onClose:(()->Void)?
    init(image:CGImage){
        let w=NSWindow(contentRect:.init(x:0,y:0,width:600,height:430),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        w.title="提取文字 · \(Product.name)";w.isReleasedWhenClosed=false
        super.init(window:w);w.delegate=self
        let root=w.contentView!,scroll=NSScrollView()
        scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder
        textView.isRichText=false;textView.font = .systemFont(ofSize:15);textView.isVerticallyResizable=true
        textView.autoresizingMask=[.width];textView.textContainer?.widthTracksTextView=true
        textView.textContainerInset = .init(width:12,height:12)
        scroll.documentView=textView
        let copy=NSButton(title:"复制文本",target:self,action:#selector(copyText));copy.bezelStyle = .rounded
        for v in [scroll,status,copy] {v.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(v)}
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:20),scroll.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-20),
            scroll.topAnchor.constraint(equalTo:root.topAnchor,constant:20),scroll.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-65),
            copy.trailingAnchor.constraint(equalTo:scroll.trailingAnchor),copy.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-20),
            status.leadingAnchor.constraint(equalTo:scroll.leadingAnchor),status.centerYAnchor.constraint(equalTo:copy.centerYAnchor),
            status.trailingAnchor.constraint(lessThanOrEqualTo:copy.leadingAnchor,constant:-12)])
        status.font = .systemFont(ofSize:12);status.textColor = .secondaryLabelColor
        w.center();showWindow(nil);NSApp.activate(ignoringOtherApps:true)
        let token=generation
        DispatchQueue.global(qos:.userInitiated).async{[weak self] in
            let result=Result{try LocalOCR.recognize(image)}
            DispatchQueue.main.async{[weak self] in
                guard let self=self,self.generation==token else{return}
                switch result {
                case .success(let text):self.textView.string=text;self.status.stringValue=text.isEmpty ? "未识别到文字，可直接在这里输入。":"识别完成，可编辑后复制。"
                case .failure(let error):self.status.stringValue="识别失败：\(error.localizedDescription)"
                }
            }
        }
    }
    required init?(coder:NSCoder){fatalError()}
    @objc private func copyText(){
        let p=NSPasteboard.general;p.clearContents()
        status.stringValue=p.setString(textView.string,forType:.string) ? "已复制文本":"剪贴板繁忙，请重试。"
    }
    func windowWillClose(_ notification:Notification){generation+=1;let done=onClose;onClose=nil;done?()}
}
final class AirDropTransfer:NSObject,NSSharingServiceDelegate {
    private var service:NSSharingService?
    private var file:URL?
    private var completion:((String?)->Void)?
    static var temporaryDirectory:URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Snapliq-AirDrop",isDirectory:true)
    }
    static func removeStaleFiles(){
        let fm=FileManager.default
        guard let files=try? fm.contentsOfDirectory(at:temporaryDirectory,includingPropertiesForKeys:[.contentModificationDateKey]) else{return}
        for f in files {
            if let date=(try? f.resourceValues(forKeys:[.contentModificationDateKey]))?.contentModificationDate,Date().timeIntervalSince(date)>86400{try? fm.removeItem(at:f)}
        }
    }
    func share(_ image:CGImage,completion:@escaping(String?)->Void){
        self.completion=completion
        do {
            let directory=Self.temporaryDirectory
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let file=directory.appendingPathComponent(UUID().uuidString+".png")
            try CaptureBackend.png(image).write(to:file,options:.withoutOverwriting);self.file=file
            guard let service=NSSharingService(named:.sendViaAirDrop),service.canPerform(withItems:[file]) else {
                finish("AirDrop 当前不可用，请检查系统 AirDrop 设置。");return
            }
            self.service=service;service.delegate=self;service.perform(withItems:[file])
        }catch{finish("AirDrop 准备失败：\(error.localizedDescription)")}
    }
    func sharingService(_ sharingService:NSSharingService,didShareItems items:[Any]){finish(nil)}
    func sharingService(_ sharingService:NSSharingService,didFailToShareItems items:[Any],error:Error){
        let e=error as NSError
        if e.domain==NSCocoaErrorDomain && e.code==NSUserCancelledError{finish(nil)}
        else{finish("AirDrop 未完成：\(error.localizedDescription)")}
    }
    private func finish(_ error:String?){
        if let file=file{try? FileManager.default.removeItem(at:file)};file=nil
        service?.delegate=nil;service=nil;let done=completion;completion=nil;done?(error)
    }
    deinit {if let file=file{try? FileManager.default.removeItem(at:file)}}
}
