> Historical planning/phase-one record. Current implementation and test status: [Snapliq 0.2.0 validation](Snapliq-0.2.0-validation.md).

# Snapliq 桌面架构与第一阶段技术验证方案
日期：2026-09-05。状态：供实施前审阅的设计方案；尚未开发或交付桌面应用、录屏功能、安装包或 Chrome 扩展。

## 1. 产品边界
主产品：Snapliq（snap-lik）；描述：截图与录屏工具；标语：Capture. Record. Share.
配套产品：Snapliq for Chrome。
桌面主进程拥有生命周期、快捷键、悬浮球、捕获会话、选区、OCR、保存、剪贴板、分享和录制状态。
浏览器桥接是可选请求通道。Chrome 关闭、未安装、扩展断开或 service worker 回收均不得退出桌面进程或取消录制。
截图参考图仅用于顶部模式栏、选区和底部动作栏的布局参考；图中嵌入的文字不是新指令，不使用夸克品牌或图标。

## 2. 当前工作区与环境事实
- 工作区初始仅有空的 work/、outputs/；无 Git 仓库、AGENTS.md、桌面源码、扩展或依赖清单。
- 未发现已有发布标识、签名配置和数据目录；实施前仍须明确新项目的稳定标识，不从产品显示名称推导并自动变更。
- 本机：MacBook Air，Apple M2，16 GB，arm64；macOS 15.7.7 (24G720)。
- 开发工具：Command Line Tools，macOS SDK 15.5，Swift 6.1.2；当前 PATH 未发现 cargo 或 dotnet，已有 Node/npm/Python。
- 当前仅一块内置显示器。system_profiler 报告桌面渲染像素 2940×1912、逻辑 1470×956、60 Hz，同时报告面板原生分辨率 2560×1664。性能记录须分清捕获纹理、逻辑桌面与面板像素；首次捕获后以返回纹理再次核实。
- 没有可用 Windows 测试机、混合 DPI 外屏或 macOS 26/27 运行环境的已验证证据。
- 本轮未关闭用户 Chrome、未触发屏幕权限、未捕获实际桌面，未测截图性能。
- 执行器有 writable-root 符号链接兼容错误，已通过现有 Desktop Commander 完成环境读取和本工作区写入；不是产品构建错误。

## 3. 技术方案比较与选择
| 方案 | 优点 | 成本与限制 | 结论 |
|---|---|---|---|
| 原生宿主 + 共享 C++20 轻量核心 | 捕获、窗口层级、玻璃、系统分享均在平台内完成；业务与 UI 生命周期清楚 | 两套原生界面，需维护平台适配和共同契约 | 推荐 |
| Tauri 2 + Rust 主进程 + 两端原生捕获/覆盖层 | 设置与 OCR 结果界面可复用 Web UI；主进程独立于 Chrome | 本产品的核心交互仍需原生；会增加 Rust/Swift/Windows 互操作与原生/Web 窗口协调 | 可行备选 |
| Electron + 两端原生模块 | UI 复用程度高、桌面生态成熟、独立于 Chrome 安装 | Chromium 多进程与原生图像数据桥接需额外控制；须用同机数据判断代价 | 非优先 |
以上性能取舍是工程判断，不是本项目实测比较。Tauri/Electron 使用 Web 技术并不意味着依赖用户的 Chrome。
参考：[Tauri 进程模型](https://v2.tauri.app/concept/process-model/)、[Electron 进程模型](https://www.electronjs.org/docs/latest/tutorial/process-model/)。

推荐组成：
- macOS：Swift + AppKit 桌面宿主；NSPanel/NSWindow 原生覆盖层与悬浮球；SwiftUI 可用于设置和 OCR 编辑结果。
- Windows：C++20 + C++/WinRT；Win32 主消息循环、托盘和覆盖 HWND；D3D11/Direct2D/DirectComposition 负责底图与选区；WinUI 3 按需承担设置、结果面板。
- 共享：小型 C++20 核心，C ABI 向 Swift 暴露；包含几何运算、选区状态机、工具栏避让、文件命名规则、录制时间计算、性能事件格式。
- 不把 CGImage、Metal texture、ID3D11Texture2D 等帧对象序列化到共享 JSON/浏览器；原生模块保有资源，核心只接收几何与状态。
- 界面不做虚假的“同一套 UI 代码”承诺。两端共享设计 tokens、品牌资产、文案、状态契约和测试用例；控件及渲染分别实现。
- 初版共享核心只抽取已经有明确两端含义的纯逻辑，不先搭建大规模插件框架。

建议支持范围：macOS 14+，Apple Silicon 先验收；Intel 构建与验收单列。Windows 首发针对 Windows 11 x64，ARM64 另设验收；Windows 10 兼容不是默认已交付范围。
选择 macOS 14 下限是为了使用 SCScreenshotManager；本机 SDK 头文件和 Apple 文档均确认其从 14.0 提供。Windows Win32 Capture interop 自 1903 可用，排除窗口值从 2004 支持，API 下限不等于产品已测试范围。
参考：[SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)、[CreateForMonitor](https://learn.microsoft.com/en-us/windows/win32/api/windows.graphics.capture.interop/nf-windows-graphics-capture-interop-igraphicscaptureiteminterop-createformonitor)。

## 4. 平台模块与接口边界
| 模块 | 输入 / 输出及职责 | macOS 实现 | Windows 实现 |
|---|---|---|---|
| DesktopRuntime | 生命周期、单实例、退出、关闭窗口、启动项 | NSApplication、NSStatusItem、SMAppService | Win32 消息循环、Shell_NotifyIcon；打包方式对应的用户启动项 |
| HotkeyService | 组合键 → 请求；返回注册状态 | RegisterEventHotKey，设置内录入与注销 | RegisterHotKey / WM_HOTKEY，MOD_NOREPEAT |
| FloatingOrb | 拖动/停靠/日历停用 → 唤醒 | 不抢焦点 NSPanel，按需截图时激活 | topmost tool HWND，明确鼠标穿透区域 |
| DisplayTopology | 显示器矩形、比例、旋转、颜色、稳定标识 | NSScreen + CoreGraphics + 捕获元数据 | EnumDisplayMonitors / DisplayConfig，Per-Monitor V2 |
| CaptureBackend | SnapshotRequest → 每屏纹理、时间戳、变换 | ScreenCaptureKit / SCScreenshotManager | Windows.Graphics.Capture + D3D11 frame pool |
| SelectionController | 指针/键盘 → 选区、移动、八向调整 | AppKit 事件与原生绘制 | Win32 输入与原生绘制 |
| WindowResolver | 桌面点 → 有序候选窗口 | CGWindowList 信息 + SCShareableContent 元数据 | EnumWindows、DWM 可见边界、过滤 cloaked 窗口 |
| ElementResolver | 已选目标应用与点 → 控件边界或失败 | Accessibility AXUIElement | UI Automation；隔离工作线程/按需进程 |
| OCRService | 当前选区图片 → 可编辑文本 | Vision，运行时查询中英文支持 | 优先 Windows OCR 可用性探测；缺语言/打包条件时使用随应用分发的本地 OCR 引擎 |
| ImageExporter | 不可变选区图像 → 剪贴板/PNG | NSPasteboard PNG/TIFF、ImageIO | CF_DIBV5 + PNG 格式、WIC |
| FileAccess | 文件夹选择、另存为、写入结果 | NSOpenPanel / NSSavePanel、bookmark | IFileDialog / 保存选择器、ACL 与磁盘错误 |
| ShareService | 文件 URL → 系统分享结果 | NSSharingService.sendViaAirDrop | 不提供 AirDrop 主按钮 |
| RecordingService | 来源/音频选项 → 真实录制状态与文件 | SCStream + AVAssetWriter/VideoToolbox | WGC + Media Foundation、WASAPI |
| BrowserBridge | 有限本地命令/DOM 候选 → 请求响应 | 应用随包 bridge + Unix domain socket | 应用随包 bridge + named pipe |

CaptureBackend 和 ElementResolver 彼此独立。OCR、Accessibility/UIA 初始化与浏览器通信不得进入截图关键路径。
Windows OCR 首选 API 的可用性、语言包与包身份要求须做专项探测，未验证前不承诺所有机器免下载；任何补充模型只在用户启用 OCR 时处理。
系统捕获与界面访问来源：[Apple 捕获示例](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)、[Microsoft 捕获说明](https://learn.microsoft.com/en-us/windows/apps/develop/media-authoring-processing/screen-capture)、[UI Automation 线程规则](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-threading)。

## 5. 生命周期和桌面悬浮球
关闭设置仅销毁/隐藏设置窗口。仅“退出 Snapliq”执行录制收尾、保存设置、注销快捷键、销毁悬浮窗口和退出主循环。
录制中明确退出应用时提示结束录制并退出，等待封装完成；不是默默丢弃录制。
开机启动默认关闭，由用户在设置启用；状态以系统实际注册结果为准。
悬浮球左键截图；拖动超过阈值才开始移动；右键原生菜单严格为“仅今天停用 / 停用 / 分隔线 / 设置”。
这些“停用”仅指悬浮球，快捷键和菜单栏/托盘仍可使用；菜单栏/托盘永远提供“显示悬浮球”与“退出 Snapliq”。
保存 permanentHidden 和 disabledLocalDate 两种独立状态。临时停用记录当时本地日期；当前本地日期不同时恢复。
在启动、唤醒、时区/时钟变化、应用重新激活和本地午夜校验；下一个本地午夜使用日历计算，不固定加 24 小时。
永久停用优先于临时停用。保存 displayID + 靠边方向 + 沿边比例，外屏消失时约束回当前可见屏，不能遗留到屏外。
macOS 评估 joinAllSpaces/fullScreenAuxiliary，检查 Spaces、Stage Manager、全屏窗口和 Mission Control。Windows 测试虚拟桌面、无边框全屏与独占全屏。
不承诺安全桌面、锁屏、独占全屏或全部窗口层级可置顶。限制场景可从快捷键/系统菜单恢复，按实测写明。

## 6. Command + X 冲突处理
本轮已做瞬时探测，未安装快捷键服务：
- RegisterEventHotKey，虚拟键 7、cmdKey 256，普通模式返回 OSStatus 0，注销返回 0。
- 同组合独占模式返回 OSStatus 0，注销返回 0。
- 没有事件处理器，未测试真实按键派送，也未操作用户文档的剪切。
- 这只反映本机探测当时接受注册；后续其他应用可能改变占用。非独占注册成功尤其不能证明无人竞争。

Command+X 是 macOS 常用剪切组合。产品将其作为用户指定的默认候选，启用前显示明确冲突说明：
“启用 Command+X 全局截图会占用常用剪切快捷键，可能使其他应用无法用该组合剪切。可继续使用，或在这里更换组合。”
不能承诺同一按键同时无冲突执行剪切和截图，不能通过延迟猜测输入框来暗中分流。
正式使用还要测试 TextEdit、Finder、浏览器输入框和其他快捷键工具的共存、修改/注销后的剪切恢复。
可提出 Command+Shift+X 或 Command+Option+X 作为备选，但须用户确认且重新探测；本轮未擅自替换默认。
优先使用系统 hotkey API，不为简单快捷键引入读取全部按键的全局 event tap。
参考：[Apple 键盘快捷键](https://support.apple.com/en-us/102650)。注册行为另由本机 macOS SDK CarbonEvents.h 核查。

## 7. 截图闭环与坐标
状态：Idle → PreparingCapture → Selecting → Exporting → Idle；取消或失败均清理资源并回到常驻。
1. 收到唤醒请求，合并连发，开始同一个 capture session。
2. 准备最新显示拓扑，暂停智能命中更新，隐藏悬浮球；底图的捕获 filter 同时排除本工具窗口。
3. 底图采集之前不显示覆盖层；截图捕获后再展示含有真实底图的覆盖层。等待合成器可见状态确认/实际捕获排除，不使用猜测性的固定睡眠。
4. 每个显示器一个原生覆盖窗口，用共享 session 保持跨屏拖拽与选区一致。底图就绪前可有立即按压反馈，但不能记作“可框选”。
5. 拖动手动框选；八向缩放/移动；像素尺寸来自最终输出变换；Esc 取消，Enter 与完成一致。
6. “完成”默认复制图片并收起，设置允许改为保存；复制/保存成功才提示完成，失败保留可重试选区。OCR 和 AirDrop 是单独动作。
7. 屏幕配置在框选中变化时取消并提示重新截图；不按旧坐标导出错误内容。
顶部模式栏居于活动屏顶部中间。底栏优先选区下方靠右，依次尝试上方/侧边并约束屏幕可用区域。
全屏选区不存在完全不重叠的外部空白：使用屏边紧凑栏、允许隐藏并以 Enter 完成；导出始终取不可变底图。

每屏保留逻辑矩形、捕获纹理宽高、旋转、颜色空间及 local-to-pixel 变换；禁止拿单一主屏 scale 乘整个虚拟桌面。
macOS 底部原点与捕获顶部原点的转换封装在适配器。Windows PMv2 物理桌面坐标与每 HWND 的 DIP 转换分别保存，不构造一个错误的“全局统一 DIP 平面”。
选区按与各屏矩形交集分片，左上 floor、右下 ceil、夹在纹理边界内，最终尺寸由输出画布计算；测试负坐标、旋转、镜像和非整数缩放。
单屏截图使用返回捕获纹理像素。跨不同像素密度屏幕必须明示统一输出策略：建议保留逻辑布局，以所涉及显示器最高采样密度合成，低密度片段将被重采样。
此策略能保留桌面几何关系，但不能同时保证所有屏幕片段都逐像素不缩放；可另外提供“各屏原始片段”导出作为高保真选项。
Windows PMv2 下物理布局无需为 UI 缩放倍率重复放大，平台适配器只按实得纹理采样密度转换。
跨屏帧不是硬件同步曝光，记录各屏采样时间差；明显超限或拓扑不一致的底图不能默默合成。
首版输出 PNG/sRGB SDR；HDR 来源需验证 tone mapping 和颜色元数据，不把泛白截图当正常。玻璃/遮罩从不进入导出渲染管线。
参考：[Windows 高 DPI](https://learn.microsoft.com/en-us/windows/win32/hidpi/high-dpi-desktop-application-development-on-windows)。

## 8. 智能框选分层
第一层窗口边界作为稳定基础。唤醒前缓存 z-order、窗口边界与 PID/窗口 ID，排除自身全部窗口。
第二层仅在用户启用且系统允许时读取可访问控件。macOS 从目标 PID 的 AX 树查询，Windows 从目标 HWND 的 UIA 根查询并检查几何。
不得直接对顶层覆盖窗口做全局命中后把自身当目标。超时、控件失效、权限不足、透明/自绘应用均退回窗口或手动选择。
鼠标更新候选建议限 30 Hz，元素查询建议上限 10–15 Hz；这些是初始参数，经测量调整。只保留最新指针请求，去重相同边界。
AX 消息设置超时；UIA 跨进程调用放独立工作线程，必要时应用自带按需 helper 隔离挂起。helper 为桌面内置模块，不是用户另装伴侣。
不在 mousemove 中截图、OCR、扫完整控件树或请求网络模型。候选单击确认，拖动越过阈值立即转手动。
第三层 Chrome DOM 仅补充可见页面元素：校验页面缩放、devicePixelRatio、滚动、浏览器内容区与系统窗口映射；不匹配时丢弃候选。
不宣称所有应用内部控件都能识别。Windows 不使用 uiAccess 或管理员提权来强行访问受限程序。
参考：[Windows UIA 安全边界](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-securityoverview)。

## 9. 保存、剪贴板、OCR、AirDrop
图片复制写入真实图像数据，至少通过系统预览/画图和一款聊天应用粘贴回读验证，而非验证路径字符串。
默认文件夹由系统目录选择器设定。首次未设定时引导选择；默认保存用原子创建避免重名覆盖，另存为才由系统弹窗确认覆盖。
处理磁盘满、只读目录、卸载外盘、目录移动、bookmark 失效和 Windows ACL 拒绝；写临时文件后在目标同卷原子落盘。
macOS 非沙盒直装版仍有 TCC/文件权限；如以后沙盒分发，使用 security-scoped bookmark 并平衡访问生命周期。
OCR 只读取当前裁剪图片；首次使用再加载中英文能力，后台队列执行，结果可编辑/复制，取消不改变截图原图。
AirDrop 是 macOS 正式模块：NSSharingService(named: .sendViaAirDrop)，检查 canPerform，创建专用临时 PNG URL，交给系统选择设备。
服务/代理对象存活到终态；成功、取消、失败分别呈现。用户取消不报“已发送”；如果系统不能细分某状态，不捏造状态。
临时文件在系统明确释放后清理，异常退出遗留于下次启动按保留期回收，禁止分享中提前删除。
Windows 不显示 AirDrop 主按钮。分享设置和默认保存位置不受 Chrome 下载目录约束。
参考：[AirDrop 分享服务](https://developer.apple.com/documentation/appkit/nssharingservice/name/sendviaairdrop)。

## 10. 权限与分发
| 能力 | macOS | Windows | 申请时机 |
|---|---|---|---|
| 桌面截图/录制 | 屏幕与系统音频录制相关 TCC，按 OS 版本展示说明 | WGC 能力/策略检查，捕获 picker 或 Win32 interop 路线分别验证 | 用户首次截图/录制 |
| 控件智能识别 | Accessibility 可选授权；未授权不阻止手动截图 | UIA provider 与进程完整性边界；无等同 macOS 的单一 AX 授权框 | 用户启用增强智能框选 |
| 麦克风 | NSMicrophoneUsageDescription + TCC；签名 entitlement 按实际 API/分发配置 | 系统麦克风隐私与设备可用性 | 用户打开麦克风 |
| 系统音频 | 按目标系统版本与 SCStream 支持检测 | WASAPI loopback；设备与受保护流限制 | 用户开启系统声音 |
| 默认文件夹 | 目录选择、文件权限；沙盒另做 bookmark | 文件选择、ACL、受控文件夹访问 | 用户设置路径/保存失败重授权 |
| 开机启动 | SMAppService 和系统管理状态 | 对应打包方式的用户启动项 | 用户显式启用 |
| AirDrop | NSSharingService 系统流程；不为此要求全盘访问 | 不适用 | 用户点击 AirDrop |
| Chrome 网页增强 | 扩展按需 activeTab/scripting/nativeMessaging | 同左 | 最后阶段，用户调用网页功能 |

无需把 Full Disk Access、录屏权限和 Accessibility 混成一次强制“大授权”。不默认申请摄像头或录音。
macOS 首选 Developer ID 签名、Hardened Runtime、公证并 staple 的 DMG。本地 ad-hoc 包只算开发验证，不声称已签名可发布。
Windows 首选签名安装程序，评估 MSIX 的更新/启动项/桥接注册与企业安装需求后定具体封装；WinUI runtime 随安装处理，不能让 Chrome 承担依赖。
签名证书、开发者 Team ID、包 ID、扩展 ID、数据目录标识与显示名称分离；当前不存在可沿用配置，不虚构证书。
源码无网络截图/OCR关键路径；日志只记耗时、状态和匿名显示配置，默认不写截图/识别文本/窗口标题。

## 11. 录屏设计和首版范围
第一阶段只验收手动截图。随后录屏首个版本支持一块屏幕或一个窗口来源、开始/暂停/继续/停止/时长、可选麦克风和实测可用的系统声音。
macOS SCStream 交付帧/系统音频，AVAssetWriter 完成封装，VideoToolbox 按硬件支持编码；较旧版本麦克风可独立 AVFoundation 捕获。
Windows WGC 只承担画面帧；音频用 WASAPI，编码/封装用 Media Foundation。系统声音不承诺只包含目标窗口，来源与范围在 UI 中说清楚。
状态：Idle → ChoosingSource → Starting → Recording ⇄ Paused → Stopping → Finalizing → Completed/Failed。
暂停/继续由媒体时间轴去掉暂停时长，视频和所有音轨统一时间基；不能仅停计时标签，也不能把暂停空档写入最终文件。
开始录制状态必须等实际帧/编码路径启动成功；停止完成必须等文件封装结束。悬浮球状态由 RecordingService 推送。
有界帧队列、复用纹理、按帧归还池；编码滞后采取限流/丢帧策略并计数，不无限堆积内存。默认不常驻 SCStream/WGC 捕获会话。
窗口关闭、显示器移除、权限撤销：有序结束并尽可能保全已录制片段，提示具体原因。
休眠/锁屏：停止并封装，唤醒不偷偷恢复采集；音频设备移除先暂停录制并让用户选择替代设备或静音继续。
设备丢失和编码异常释放资源，保留可恢复片段；崩溃恢复不等于保证未封装 MP4 完好，评估分段/fragmented 容器。
macOS 使用 SCContentFilter 排除自身应用/窗口；Windows 自己拥有的 top-level HWND 设置 WDA_EXCLUDEFROMCAPTURE 并实际验证。
若某环境排除无效，录制开始前隐藏球与控制条，改为快捷键和状态菜单控制；状态菜单若位于被录屏幕上仍可能入片，须明确提示。安全/受保护内容遵循 OS 限制。
区域录屏建议不进入录屏首版：须增加 GPU 裁剪、编码对齐、旋转/DPI变换、来源 resize、音画同步和跨屏合成。
单屏固定区域的预估附加开发验证量为 4–7 人日，跨屏动态区域再增加 5–10 人日；这是初步规划范围，不是工期承诺，依平台探测调整。
不能用截图框 UI 或仅 sourceRect 配置就声称区域视频已验收。
参考：[WGC 捕获](https://learn.microsoft.com/en-us/windows/apps/develop/media-authoring-processing/screen-capture)、[WASAPI loopback](https://learn.microsoft.com/en-us/windows/win32/coreaudio/loopback-recording)、[排除录制窗口](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity)。

## 12. Liquid Glass 与品牌设计系统
Apple 文档元数据核实：NSGlassEffectView 从 macOS 26.0 可用；effectIsInteractive 为 macOS 27.0 Beta 属性。
- macOS 14/15：NSVisualEffectView + 原生控件 + 明确边界；减少透明度时使用实色，不称为原生 Liquid Glass。
- macOS 26：NSGlassEffectView / 必要时 NSGlassEffectContainerView。
- macOS 27：条件启用 effectIsInteractive，单独验证 Beta 变化；不能使截图闭环依赖 Beta API。
- 编译也需要有对应 API 的 SDK；仅运行时 #available 不能让本机 15.5 SDK 凭空识别新类型。采用新 SDK 构建兼容低版本的正式构建，旧 SDK 开发时独立排除 glass 源文件。
- Windows：评估 Acrylic/系统 backdrop 与 DirectComposition，关闭透明度、高对比、节电及不支持时使用实色。Mica 不是桌面实时透视的同义词，不宣称 Apple 材质。
玻璃只用于悬浮球、模式/动作栏、轻量面板，优先系统菜单。文本与图标必须在复杂背景上有足够对比；阴影不作用于导出底图。
Apple 当前 macOS 27 官方文档仍以 Beta 说明展示，实施时重新核对具体 SDK、OS build 和 release notes，不推定最终发行行为。
参考：[NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)、[27 交互属性](https://developer.apple.com/documentation/appkit/nsglasseffectview/effectisinteractive)、[macOS 27 发布说明](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)、[Windows backdrop](https://learn.microsoft.com/en-us/windows/apps/develop/ui/system-backdrops)。

品牌设计稿和小尺寸规则见同目录 design-system/snapliq/MASTER.md。
纯平符号先行：两枚左上/右下 L 角 + 分离圆点，黑白成立后才做材质；本轮交付比例设计规则，不冒称矢量/安装资源已经生成。
macOS 使用可编辑分层 SVG/PDF 导入 Icon Composer，背景、符号、点独立；系统遮罩/高光/折射不重复烘焙，最终 .icon 与旧系统 AppIcon/.icns 同时验收。
Windows 输出一致的静态多尺寸 .ico 及安装资源；菜单栏/托盘专用简化符号，Chrome 输出工具栏与 manifest PNG；圆形悬浮球不嵌入方形 Dock 图标。
检查 16/24/32/64 px 与大尺寸，实际 1×/2× 比例；品牌符号不是现成图标库复制品。
参考：[Apple app icons HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons)、[Icon Composer](https://developer.apple.com/icon-composer/)。

## 13. 第一阶段技术验证与验收顺序
V0：环境与设计证据（本轮）。完成工作区盘点、官方 API 核实、Skill 安装/设计检索、Command+X 注册/注销探测；尚无截图数据。
V1：macOS 独立最小 .app。稳定开发 bundle ID、NSApplication 主循环、菜单栏、设置关闭仍常驻、快捷键服务、原生悬浮球。
V2：捕获技术 spike。SCScreenshotManager filter 路线与按需 SCStream 首帧路线同设备对照；均禁止空闲连续录制。测冷/热资源、滤除球、捕获正确像素。
V3：手动选区闭环。真实底图、缩放/移动、尺寸、Esc/Enter、图片复制、目录选择、保存/另存为、错误保留选区。
V4：多屏与性能。单屏 Retina 后，再借助真实外屏验证负坐标、混合 scale、跨屏、拔插、全屏 Spaces、休眠恢复及停用日期。
V5：Windows 同一契约的独立版本。先 WGC + Win32 capture spike，再接选择/托盘/剪贴板/保存；不能仅因 macOS 通过就打勾 Windows。
V6：生成可安装开发包、接入平面品牌和小尺寸资源，执行独立性验收。正式签名公证由对应证书和运行环境完成后另行标记。
第一阶段不放看似可用的 OCR/AirDrop/录屏假按钮；目标完整布局在设计系统中保留，能力完成后接入。

### 度量协议
使用 monotonic clock；macOS signpost/ContinuousClock，Windows QPC/ETW。每次会话有唯一 ID。
T0=原生热键事件进入宿主（另用高帧率外部测量核对物理按键到可见反馈）；Tfeedback=真实首次可见反馈；
Tbackground=所有请求显示器底图实际就绪；Tselectable=真实底图已提交显示并接受拖动；Tconfirm=确认；Tcopy=系统剪贴板成功提交。
必须分别报告 Tfeedback-T0、Tbackground-T0、Tselectable-T0、Tcopy-Tconfirm；UI 出现和底图就绪分开记录，不把回调触发当屏幕呈现。
系统 API 提交时刻与物理呈现有误差，报告刷新率和至少一组外部可见测量；不伪造亚毫秒屏幕可见时间。
开发初始预算（不是实测）：热启动首次反馈 P95 ≤50ms；底图 P95 ≤150ms；可框选 P95 ≤180ms；典型约 2MP 选区复制 P95 ≤120ms。达不到则定位瓶颈后调整方案，不改统计定义掩盖。
每配置至少 100 次已授权常驻唤醒；冷进程首截单列至少 30 次；首次权限弹窗另列，不合入热启动。
P50/P95 使用 nearest-rank，记录原始样本、样本数、失败/取消率；失败不得从报告中静默消失。
报告设备、OS/build、CPU/GPU、内存、捕获纹理尺寸、逻辑尺寸、面板像素、刷新率、显示缩放、屏幕数量、HDR、供电、构建模式和版本。
另测常驻空闲 10 分钟的 CPU/RSS/wakeups、100 次连续截图后的内存平台、录屏后续 30–60 分钟 RSS/队列/丢帧/文件完整性。
静默常驻只可缓存枚举元数据、分配窗口/设备资源；不得默认采集历史帧以粉饰热启动结果。

### 核心验收清单
- Chrome 完全退出：实际进程检查 + 快捷键/球截图 → 拖选 → 在外部应用粘贴图片 → 保存真实 PNG → 应用继续常驻。
- 未安装扩展：上述完整闭环通过。未安装 Chrome 的干净用户/机器再验，不通过卸载用户现有 Chrome 来测试。
- 关闭设置窗口：快捷键继续有效；仅退出 Snapliq 后快捷键注销，常用剪切恢复。
- 默认目录取消/失效/只读/重名时有正确反馈，截图内容可重试。
- 球停用仍能从菜单恢复；临时停用跨本地午夜、休眠、重启、时区变化恢复正确。
- 实际捕获图不包含 Snapliq 球、覆盖层和工具栏；跨屏无偏移/截断。
- 未授权/受保护内容/不支持系统：明确状态，不把空白或旧底图当成功。
- 第一阶段完成后才验证 OCR、AirDrop 的真实用户流程和录屏，最后接扩展。
- 录屏阶段追加：录制中退出 Chrome、关闭设置仍连续；源关闭/休眠有正确封装；打开最终文件核对音画、控制条排除和时长。
- 每个测试标“通过/失败/未测试”，另附设备证据；没有 Windows/多屏实机就保持未测试。

## 14. 最后接入 Chrome
扩展由用户动作发 native messaging 请求。随桌面安装的轻量 native host 只负责请求转发/可选启动主应用，不拥有截图/录制状态。
Chrome 终止 host 时仅断开桥接；桌面主应用由自己的启动路径和生命周期继续运行，不继承 pipe 断开退出逻辑。
限定扩展 ID、消息 schema/长度、动作白名单、超时/去重；UDS/named pipe 限当前用户并验证对端。无开放未鉴权 localhost 控制端口。
DOM 信息仅作为候选矩形提示，不能附带任意文件路径或命令执行能力。大图不通过 native messaging JSON 搬运。
扩展请求失败显示“打开 Snapliq / 重试”；不暗中切换成标签页截图冒充系统截图。
参考：[Chrome Native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)。

## 15. 实施前审阅点
推荐批准原生宿主 + 共享轻量核心、macOS 14+/Windows 11 的初始范围与先 macOS 后 Windows 同契约验证顺序。
Command+X 保留为指定候选，正式启用须接受剪切冲突提示；若改组合由用户确认。
当前待办是实现以上 V1–V6；本文件不是运行完成报告。性能百分位、两端安装包、原生玻璃和最终品牌资产均未冒充已完成。
