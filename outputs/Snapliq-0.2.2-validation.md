# Snapliq 0.2.2 桌面 App 开发验收
2026-09-13。按用户要求优先交付桌面 App，Chrome 扩展开发与商店提交暂缓。

## 可交付文件
- outputs/builds/0.2.2/Snapliq.app
- Snapliq-0.2.2-macOS-arm64-development.dmg：含 App、Applications 快捷方式和中文使用说明；挂载后版本/严格签名检查通过。
- Snapliq-0.2.2-macOS-arm64-development.zip
- Snapliq-0.2.2-source.zip

macOS 14+、Apple Silicon。开发 Bundle ID 和数据目录保持原样；使用临时签名，未 Developer ID 签名、公证。CDHash：e923d2c31d1df5e1cc5615465d4c1fa2ea2c49ab。0.2.1 已授权 App 和交付包保留。

## 新增桌面行为
- 录屏面板 → 框选录制区域 → 拖动/移动/调整选区 → Enter 使用区域 → 原生保存面板 → 录制。确认选区本身不会开始录制，也不会改写剪贴板。
- 截图状态已有选区时，顶部“屏幕录制”会把选区带入录屏面板。
- 通过显示器 SCContentFilter + SCStreamConfiguration.sourceRect 原生裁剪后编码。不是记录整屏再只改变预览框。
- 单显示器内支持负坐标、Retina 和按像素向内对齐；H.264 宽高使用偶数像素并在来源名称中显示实际输出尺寸。跨屏、过小选区明确报错；保存对话框之后重新验证显示器和缩放。
- 捕获显式使用 sRGB，视频写入明确的 BT.709 原色、传递函数及矩阵标记，修复测试中出现的纯色偏差。HDR/广色域完整管理仍不在本次验收范围。

## 已通过
设备：MacBook Air M2 / 16 GB，macOS 15.7.7，单屏 1470×956 pt、2940×1912 捕获像素；编译 SDK 15.5。

| 检查 | 结果 |
|---|---|
| 桌面 App 编译 | macOS arm64 0.2.2 完整构建，嵌套桥接器及 App 严格签名验证通过 |
| 共享几何 | 1972 个边界用例通过 |
| 区域映射 | 750 个负坐标/分数比例用例，Retina、向内偶数像素对齐、过小/跨屏拒绝、拓扑失效通过 |
| 真正视频裁剪 | 生成四象限原生窗口，偏离中心的 220×170 pt 选区编码为 440×340 px；解码后四象限和边界附近共 8 个探针通过 |
| 排除自身覆盖层 | 测试宿主的洋红色窗口覆盖整个目标区域；成片仍是其下的四色图案，无洋红覆盖层 |
| 暂停和封装 | preparing → recording → paused → recording → finishing → idle；有效视频 2.556667 秒，66 个解码帧 |
| 视频时间戳与解码 | 包 DTS 与解码帧显示时间均严格递增；保留源时间基的 ffmpeg 完整解码无错误 |
| 选区原生 UI | 仅显示取消/使用区域；按钮不越界；Enter 返回正确尺寸且不改剪贴板；Esc 清理所有遮罩 |
| 截图回归 | 原有 407 pt 工具栏、可编辑 OCR、文本复制、恢复选区及真实 PNG 复制通过 |
| 服务回归 | 本地中英文 OCR、暂停/静态画面时间轴、桥接协议和智能命中缓存测试通过 |
| DMG | hdiutil 校验通过；只读挂载后 App 版本、签名、Applications 链接检查通过 |

原生视频、选区和 OCR 测试使用相同产品模块的独立测试宿主。证据见 evidence/v0.2.2；不能把测试宿主授权视为最终 App 已授权。

测试记录保留了默认 ffmpeg null 输出时间基造成的 DTS 舍入警告。核对文件中包 DTS 与解码帧 PTS 均递增后，以 `-fps_mode passthrough -enc_time_base demux` 完整解码通过；测试脚本已采用该检查方式。四色测试初次失败还发现了未明确颜色标记的问题；修复后保留原有颜色阈值，并新增了边界探针。

## 最终 App 当前授权状态
已打开 0.2.2 App。快捷键注册 status=0/enabled=true；真实 PNG 剪贴板、负坐标 Retina 裁切及不覆盖重名文件自检通过。系统返回 screenPermission=false，因此最终新包的屏幕截图/录屏整包回归待授权。没有修改 TCC 数据库，也没有覆盖 0.2.1。

用户操作：在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许当前 Snapliq，按系统提示退出并重新打开。若先安装到 Applications，应为该安装位置的 App 授权。本次不把旧版性能数字写成 0.2.2 的性能结论。

## 剩余范围
Windows 源码保留但无编译/实机验收；区域视频目前仅 macOS 单屏。多物理显示器/混合 DPI、跨屏视频、麦克风和设备变化、真实休眠撤权、跨设备 AirDrop、macOS 26/27 原生玻璃及 .icon、正式签名公证仍待完成。Chrome DOM 增强未实现，商店提交暂停。

## 依据
Apple sourceRect 文档：https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/sourcerect
安装的 ScreenCaptureKit SCStream.h 指定 sourceRect 为显示器逻辑点，destinationRect 为像素；本轮通过实际视频验证方向与缩放。UI UX Pro Max 的原生控件、焦点和遮挡检查应用于现有 Snapliq 设计系统。
