import AppKit
/// Routes every control through the native material's content view. The exported image uses the capture bitmap.
final class MaterialSurface:NSView {
    private let content=NSView()
    private var effect:NSView?
    private let radius:CGFloat
    private var initializing=true
    init(radius:CGFloat){
        self.radius=radius;super.init(frame:.zero)
        configure();initializing=false
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(configure),name:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil)
    }
    required init?(coder:NSCoder){fatalError()}
    deinit{NSWorkspace.shared.notificationCenter.removeObserver(self)}
    override func addSubview(_ view:NSView){if initializing{super.addSubview(view)}else{content.addSubview(view)}}
    @objc private func configure(){
        content.removeFromSuperview();effect?.removeFromSuperview()
        let surface:NSView
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let solid=NSView();solid.wantsLayer=true;solid.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor
            solid.layer?.cornerRadius=radius;surface=solid;solid.addSubview(content)
        }else{
            #if SNAPLIQ_GLASS
            if #available(macOS 26.0,*) {
                let glass=NSGlassEffectView();glass.cornerRadius=radius;glass.contentView=content;surface=glass
            }else{surface=fallback()}
            #else
            surface=fallback()
            #endif
        }
        content.frame=bounds;content.autoresizingMask=[.width,.height]
        surface.frame=bounds;surface.autoresizingMask=[.width,.height]
        effect=surface;super.addSubview(surface)
    }
    private func fallback()->NSView {
        let visual=NSVisualEffectView();visual.material = .hudWindow;visual.blendingMode = .behindWindow;visual.state = .active
        visual.wantsLayer=true;visual.layer?.cornerRadius=radius;visual.layer?.masksToBounds=true;visual.addSubview(content);return visual
    }
    override func viewDidChangeEffectiveAppearance(){super.viewDidChangeEffectiveAppearance();if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency{effect?.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor}}
}
