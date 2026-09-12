# Snapliq 0.2.0 开发候选验收
更新时间：2026-09-08。桌面应用是主产品，Chrome 为可选入口。本报告替代当前能力描述，不抹去早期 0.1.0 阶段记录。

## 交付状态

| 内容 | 当前状态 |
|---|---|
| macOS 原生截图主流程 | 已构建、运行、系统快捷键到真实 PNG 的两轮各 100 次回归通过 |
| macOS 本地 OCR、原生 AirDrop、原生录屏 | 已实现；OCR 编辑复制、AirDrop 取消清理、屏幕录屏暂停/继续/停止已验证 |
| macOS 智能框选 | 窗口信息与可选 AX 控件命中源码已接入；广泛真实应用控件识别尚未验收 |
| Windows 桌面宿主和平台服务 | WGC、Win32、UIA、OCR、MF/WASAPI、托盘/悬浮球/保存/桥接源码及安装脚本已提供；未编译、未实机测试 |
| Snapliq for Chrome | MV3 与本地桥接已实现；真实 Chrome 加载、连接 0.2.0、打开桌面设置已验证；无 DOM 增强 |
| 品牌资产 | 原创 SVG、黑/白、深/浅应用图标、小尺寸与平台资源已生成并接入构建 |
| Liquid Glass | NSGlassEffectView 条件编译源码已接入；本机实际构建和验证的是 NSVisualEffectView 降级 |
| 正式发行 | 未完成 Developer ID/公证、Windows 签名、商店发布、.icon 编译和完整跨平台验收 |

候选路径：outputs/candidate/Snapliq.app，版本 0.2.0，Apple Silicon arm64，最低 macOS 14。
Bundle ID：com.snapliq.desktop.development；数据目录：Snapliq Development。
签名：ad-hoc，CDHash **e50b670d60e2bda9c4062e15570de335d3ff3eb6**。
本轮没有重建或重签该应用。旧 outputs/Snapliq.app 与旧压缩包保留。

## 测试设备与方法

MacBook Air M2，16 GB；macOS 15.7.7 (24G720)；Xcode Command Line Tools SDK 15.5、Swift 6.1.2。一块内置屏幕，逻辑 1470×956、实际捕获 2940×1912、60 Hz，面板标称原生 2560×1664。逻辑尺寸、捕获尺寸和面板像素不能混同。未接第二块物理显示器。

2026-09-08 新测量使用 TimedKey 在 CGEvent key-down 提交前记录 systemUptime，再与桌面事件日志比较。Cmd+X 唤醒，鼠标从 (300,240) 拖至 (720,480)，Enter 完成。每次读取系统剪贴板 PNG，确认 840×480；100 次均通过，Chrome 每次均完全退出。首个唤醒样本保留，没有丢弃暖机样本。系统没有后台持续录像或屏幕历史预热。

| 测量区间 | P50 | P95 |
|---|---:|---:|
| Cmd+X 事件发出 → 首次反馈提交 | 19.99 ms | 20.85 ms |
| Cmd+X 事件发出 → 干净截图底图就绪 | 66.70 ms | 69.52 ms |
| Cmd+X 事件发出 → 选区可用事件 | 145.35 ms | 254.20 ms |
| Enter 事件发出 → 图片写入剪贴板完成 | 114.53 ms | 121.41 ms |

P50/P95 使用排序后的线性插值。反馈和选区可用是应用提交及后续 run loop 事件；**未测物理按键扫描、合成器真正呈现或屏幕光子延迟**。不将先显示反馈视图视为底图已经捕获。复制区间包括系统按键分发和主线程调度；不能与仅围绕 PNG 编码/剪贴板函数计时的旧数值直接比较。

前一轮 0.2.0 应用内部计时（2026-09-06，录屏回归后的温态，100/100）保留用于追踪：反馈 5.42/10.71、底图 73.39/81.51、可用 154.27/286.77、复制 13.23/14.08 ms（P50/P95）。它的起点在部分分发与权限检查之后，不能标为完整快捷键端到端性能，也不能据此断言本轮复制性能退步。

证据：[新计时](evidence/v0.2.0/capture-performance-system-events.json)、[100 个样本](evidence/v0.2.0/capture-samples-system-events.json)、[旧内部口径](evidence/v0.2.0/capture-performance-internal-previous.json)。复现说明见 docs/testing.md，脚本 scripts/benchmark-interactive-macos.py；原始实测脚本和诊断留在本地 work。

## Chrome 独立性与真实录屏

2026-09-06 在候选应用开始屏幕录制后退出 Chrome，录制进程保持存活；之后暂停、继续，并关闭原生设置窗口，录制仍继续，最终由原生控制条停止。最终事件为 recording_finished：
- 147.482681 秒、4,315 个写入帧、应用编码队列记录丢帧 0。
- MP4 容器时长 147.535334 秒，37,749,138 字节。
- H.264 2940×1912；AAC 48 kHz 双声道。
- 2026-09-08 使用 ffmpeg 对全部视频和音频解码，退出码 0、错误日志 0 字节。编码队列的 0 丢帧不证明屏幕呈现每个源帧均被捕获。
- 在 100 秒处抽帧：控制条原位置 (1130,120,680,104) 与悬浮球原位置 (2824,700,96,96)，坐标为成片像素。两个矩形内 Y/U/V 最小值与最大值均为 107/154/104，仅剩生成底图，未出现 Snapliq 控件。这是单次录制抽样证据，不能替代所有来源/窗口/系统版本的排除测试。
- 其他应用的悬浮窗正常出现在桌面成片中；排除本工具不等于排除所有第三方悬浮窗口。

视频包含真实桌面和可能来自其他应用的系统声音，只保留本地 work/regression-v0.2，未纳入源码或公开证据包。未把声音非零等同于纯测试音来源。
证据：[独立性结果](evidence/v0.2.0/recording-independence.json)、[媒体结构](evidence/v0.2.0/recording-probe.json)、[解码与排除范围](evidence/v0.2.0/recording-decode.json)。

未安装扩展时，早期桌面截图闭环与服务测试已经通过；扩展是在原生服务实现及运行验证后加入。0.2.0 后续在 Chrome 完全退出时又通过 100 次系统快捷键截图。适配器 EOF 后桌面进程继续运行；设置关闭日志确认 applicationContinues，后续快捷键截图成功。

## 其他验证

| 检查 | 结果及范围 |
|---|---|
| 几何与图片流水线 | 1,972 边界用例；负坐标、分数像素、裁切、合成混合密度、PNG roundtrip、10 个重名安全保存、权限错误及临时清理通过；混合 DPI 是生成数据测试 |
| 中文英文 OCR | Vision 本地识别 Snapliq Capture 123 / 截图与录屏工具；真实 AppKit 编辑后复制文本、关闭面板恢复选区、复制图片通过 |
| 工具栏可见范围 | 补测六个按钮均处于真实窗口范围，宽度不少于文字 intrinsicContentSize；当前 382 pt 面板下全部通过。创建宽度 590 与放置宽度 382 的配置仍需后续统一和增加留白，本轮不改动签名 |
| 视频暂停 | 生成帧测试中移除 2 秒暂停间隔，60 帧输出 2.0 秒 |
| 来源窗口关闭 | 真实 SCK 独立窗口来源运行约 3 秒后关闭，自动封装 3.2333 秒 MP4、控制器回到 idle；使用相同原生模块的测试宿主，不等同于所有窗口类型及最终 UI 的中断矩阵 |
| 静态画面结束 | 单帧起始加结束帧，输出 8.0 秒，未因画面静止缩短成片 |
| 系统声音 | SCK 实际 AAC 轨道与非零音频已验证；双音轨混合到单 AAC 的专项测试曾通过 |
| AirDrop | 本轮实际打开系统选择器，仅点击取消，收到回调且此次临时图片被删除。未选择接收设备，未验证跨设备送达 |
| Native Messaging | 同用户 socket 权限、帧长、action 白名单、超时、来源校验、EOF 存活、Chrome 真实连接通过 |
| 资源占用 | 本轮 100 次截图后 vmmap physical footprint 71.7 MiB，进程生命周期峰值 219.9 MiB；是单次快照，不是长时间泄漏结论 |
| 快捷键 | 当前 Cmd+X 注册状态 0、enabled true，真实事件注入可截图；仍占用普通剪切，用户已接受，不静默替换 |

日志：[核心与图片](evidence/v0.2.0/core-image-tests.txt)、[服务与桥接](evidence/v0.2.0/service-bridge-tests.txt)、[原生选区 UI](evidence/v0.2.0/selection-ui-tests.txt)、[AirDrop 取消](evidence/v0.2.0/airdrop-cancel-test.txt)、[来源窗口关闭](evidence/v0.2.0/window-closure-test.txt)、[物理内存口径](evidence/v0.2.0/memory-footprint.json)。

## 仍待完成的验收与明确不支持项

1. Windows 实机编译、启动与所有平台功能验证。用户目前没有 Windows 环境，已明确先完成源码和 macOS 验证；本次没有伪造 Windows 安装包或测试结果。
2. 第二块物理显示器、混合 DPI、负坐标排列、跨屏选区、全屏应用和 Spaces。已有共享几何用例不能代替硬件测试。
3. 真实麦克风采集、设备切换、显示器变化、休眠、权限撤销、其他异常中断及小时级内存走势。来源窗口关闭已通过原生模块真实捕获测试，其余矩阵尚未完成。
4. 更广泛 macOS Accessibility / Windows UI Automation 控件识别和完整 VoiceOver/键盘无障碍。不能保证所有自绘或提权应用的内部元素可识别。
5. macOS 26/27 原生材质、新 SDK 的真实编译/运行、Icon Composer .icon 资源及正式签名公证。当前 macOS 15 使用原生降级，Windows 是协调的替代视觉。
6. AirDrop 跨设备发送与失败、中文/英文之外的语言质量、HDR/颜色准确性。
7. 区域录屏没有实现，界面明确录制整个来源。需要实际视频裁剪、编码尺寸和音画时间轴测试才能加入。
8. Chrome DOM 补充和网页专属捕获未实现；当前扩展只做配套入口，没有将 DOM 包装成系统智能框选。

## 开发交付

- Snapliq-0.2.0-macOS-arm64-development.zip：当前已授权并验证的 App，未重新签名。
- Snapliq-0.2.0-source.zip：两平台源码、测试、品牌资产、Chrome、构建/安装器脚本、设计系统与本报告。
- Snapliq-for-Chrome-development.zip：开发者模式扩展包，未发布 Chrome Web Store。
- Snapliq-0.2.0-checksums.json：交付文件 SHA-256。
- 原创图标检查：assets/generated/brand-contact-sheet.png。macOS .icns / Windows .ico / Chrome PNG 已接入，.icon 层资源仍是源文件。

这些是可运行的 macOS 开发候选和跨平台开发源码，**不是全部需求通过的正式发行版**。不要将源码覆盖范围、单屏测试或版本号当成完整验收证明。
