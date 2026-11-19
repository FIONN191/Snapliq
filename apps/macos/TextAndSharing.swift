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
// OCR results outlive the capture session and do not restore its overlay on close.
final class OCRController {
    private var panels=[UUID:OCRPanel]()
    func present(_ image:CGImage){
        let id=UUID(),panel=OCRPanel(image:image)
        panels[id]=panel
        panel.onClose={ [weak self] in self?.panels.removeValue(forKey:id) }
    }
}
final class OCRPanel:NSWindowController,NSWindowDelegate {
    private let textView=NSTextView()
    private let status=NSTextField(labelWithString:"")
    private let copyButton=NSButton(title:"",target:nil,action:nil)
    private enum ResultStatus {case recognizing,empty,ready,copied,copyFailed,failed(String)}
    private var resultStatus=ResultStatus.recognizing
    private var generation=0
    var onClose:(()->Void)?
    init(image:CGImage){
        let w=NSWindow(contentRect:.init(x:0,y:0,width:600,height:430),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        w.isReleasedWhenClosed=false;w.setAccessibilityIdentifier("snapliq.ocr.window")
        super.init(window:w);w.delegate=self
        NotificationCenter.default.addObserver(self,selector:#selector(refreshLanguage),name:.snapliqLanguageChanged,object:Localization.shared)
        let root=w.contentView!,scroll=NSScrollView()
        scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder
        textView.isRichText=false;textView.font = .systemFont(ofSize:15);textView.isVerticallyResizable=true
        textView.autoresizingMask=[.width];textView.textContainer?.widthTracksTextView=true
        textView.textContainerInset = .init(width:12,height:12)
        textView.setAccessibilityIdentifier("snapliq.ocr.text")
        scroll.documentView=textView
        let copy=copyButton;copy.target=self;copy.action=#selector(copyText);copy.bezelStyle = .rounded
        copy.setAccessibilityIdentifier("snapliq.ocr.copy")
        for v in [scroll,status,copy] {v.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(v)}
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:20),scroll.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-20),
            scroll.topAnchor.constraint(equalTo:root.topAnchor,constant:20),scroll.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-65),
            copy.trailingAnchor.constraint(equalTo:scroll.trailingAnchor),copy.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-20),
            status.leadingAnchor.constraint(equalTo:scroll.leadingAnchor),status.centerYAnchor.constraint(equalTo:copy.centerYAnchor),
            status.trailingAnchor.constraint(lessThanOrEqualTo:copy.leadingAnchor,constant:-12)])
        status.font = .systemFont(ofSize:12);status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail;status.setAccessibilityIdentifier("snapliq.ocr.status")
        status.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        refreshLanguage()
        w.center();showWindow(nil);NSApp.activate(ignoringOtherApps:true)
        let token=generation
        DispatchQueue.global(qos:.userInitiated).async{[weak self] in
            let result=Result{try LocalOCR.recognize(image)}
            DispatchQueue.main.async{[weak self] in
                guard let self=self,self.generation==token else{return}
                switch result {
                case .success(let text):self.textView.string=text;self.resultStatus=text.isEmpty ? .empty:.ready
                case .failure(let error):self.resultStatus = .failed(error.localizedDescription)
                }
                self.refreshLanguage()
            }
        }
    }
    required init?(coder:NSCoder){fatalError()}
    @objc private func refreshLanguage(){
        window?.title=L("提取文字 · \(Product.name)","Extract Text · \(Product.name)")
        copyButton.title=L("复制文本","Copy Text")
        textView.setAccessibilityLabel(L("识别结果，可编辑","Recognized text, editable"))
        switch resultStatus {
        case .recognizing:status.stringValue=L("正在本机识别中文和英文…","Recognizing Chinese and English on this Mac…")
        case .empty:status.stringValue=L("未识别到文字，可直接在这里输入。","No text found. You can type here.")
        case .ready:status.stringValue=L("识别完成，可编辑后复制。","Ready to edit and copy.")
        case .copied:status.stringValue=L("已复制文本","Text copied")
        case .copyFailed:status.stringValue=L("剪贴板繁忙，请重试。","The clipboard is busy. Try again.")
        case .failed(let reason):status.stringValue=L("识别失败：\(reason)","Recognition failed: \(reason)")
        }
        status.toolTip=status.stringValue
    }
    @objc private func copyText(){
        let p=NSPasteboard.general;p.clearContents()
        resultStatus=p.setString(textView.string,forType:.string) ? .copied:.copyFailed;refreshLanguage()
    }
    func windowWillClose(_ notification:Notification){
        generation+=1;NotificationCenter.default.removeObserver(self)
        let done=onClose;onClose=nil;done?()
    }
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
                finish(L("AirDrop 当前不可用，请检查系统 AirDrop 设置。","AirDrop is unavailable. Check the system AirDrop settings."));return
            }
            self.service=service;service.delegate=self;service.perform(withItems:[file])
        }catch{finish(L("AirDrop 准备失败：\(error.localizedDescription)","Unable to prepare AirDrop: \(error.localizedDescription)"))}
    }
    func sharingService(_ sharingService:NSSharingService,didShareItems items:[Any]){finish(nil)}
    func sharingService(_ sharingService:NSSharingService,didFailToShareItems items:[Any],error:Error){
        let e=error as NSError
        if e.domain==NSCocoaErrorDomain && e.code==NSUserCancelledError{finish(nil)}
        else{finish(L("AirDrop 未完成：\(error.localizedDescription)","AirDrop did not complete: \(error.localizedDescription)"))}
    }
    private func finish(_ error:String?){
        if let file=file{try? FileManager.default.removeItem(at:file)};file=nil
        service?.delegate=nil;service=nil;let done=completion;completion=nil;done?(error)
    }
    deinit {if let file=file{try? FileManager.default.removeItem(at:file)}}
}
