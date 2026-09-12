# Snapliq
Capture. Record. Share. — 截图与录屏工具

Snapliq 是独立原生桌面应用。macOS 使用 Swift/AppKit + ScreenCaptureKit，Windows 使用 Win32/C++/WinRT + Windows.Graphics.Capture，两端共享 C++20 几何和布局核心。Snapliq for Chrome 仅提供配套入口；退出 Chrome、断开 Native Messaging 或关闭设置不结束桌面应用。

当前桌面开发版本 **0.2.2**：提供可运行的 macOS Apple Silicon `.app`、DMG 与 ZIP，新增单屏区域录屏并修正视频颜色标记。原生区域裁剪/暂停/封装和截图 UI 测试通过；**最终 0.2.2 App 仍需用户授予屏幕录制权限后回归**。详见 [0.2.2 验收报告](outputs/Snapliq-0.2.2-validation.md)。已验收的 0.2.1 App 保留作为回退版本，其 100 次快捷键与录屏结论见 [0.2.1 报告](outputs/Snapliq-0.2.1-validation.md)。Windows 提供源码和 GitHub Actions 构建配置；云端编译结果见 Actions，真实桌面截图、录屏及权限仍待 Windows 实机验收。Chrome 开发与商店提交暂缓。

## 启动与使用

桌面开发版下载：[macOS 安装包（DMG）](https://github.com/FIONN191/Snapliq/releases/download/v0.2.2/Snapliq-0.2.2-macOS-arm64-development.dmg) · [0.2.2 预发布说明](https://github.com/FIONN191/Snapliq/releases/tag/v0.2.2)。本仓库跟踪源码、品牌资产和验收证据；本机 App、DMG、视频和剪贴板备份不进入 Git 历史。

新构建应用位于 `outputs/builds/0.2.2/Snapliq.app`；安装文件为 `outputs/Snapliq-0.2.2-macOS-arm64-development.dmg`。已验收的 0.2.1 保留于 `outputs/builds/0.2.1/Snapliq.app`。已授权的 0.2.0 位于 `outputs/candidate/Snapliq.app`，更早的 `outputs/Snapliq.app` 也保留。0.2.1 已在恢复授权后通过最终 App 的 100 次 Chrome 退出截图、设置关闭、原生保存和录屏暂停/继续/停止回归；模块测试与最终 App 验收分别记录，不沿用旧签名结果。当前 macOS 构建要求 macOS 14+、Apple Silicon。不要同时启动两份开发应用。

首次截图需要系统屏幕录制权限。Command + X 是默认候选，只有用户接受普通剪切冲突后才启用；注册成功不代表它与剪切兼容。设置中可以直接修改快捷键。菜单栏、独立悬浮球与 Chrome 配套入口都可唤醒截图。关闭设置后继续常驻；选择「退出 Snapliq」才结束后台运行。

- 区域截图：拖动框选、移动和八点调整，显示导出像素尺寸。Enter/完成复制真实 PNG，Esc 取消，Command + C 复制，Command + S 保存。方向键移动，Option + 方向键调尺寸，Shift 加速，H 暂时隐藏底部栏。
- 下载菜单：保存、另存为、默认目录系统选择器；重名自动处理，权限失败保留选区并提示。
- 智能框选：先匹配系统窗口边界；可选 Accessibility/UI Automation 控件识别，失败退回窗口。窗口截图当前基于可见桌面区域，不恢复被遮挡内容。
- 提取文字：本地识别中文和英文，弹出可编辑结果并复制文本。macOS 使用 Vision；Windows 使用已安装的系统 OCR 语言包。
- AirDrop：macOS 直接进入系统分享服务，由用户选择接收设备。Windows 不显示 AirDrop。
- 录屏：原生屏幕/窗口来源、开始/暂停/继续/停止、时长、可选系统声音。macOS 15+ 提供 SCK 麦克风输入，macOS 14 禁用该选项。保存 H.264/AAC MP4，暂停时间从时间轴扣除。macOS 0.2.2 支持单显示器内的真实区域视频裁剪：点击“框选录制区域…”，Enter 确认区域，再选择保存文件并开始。跨屏区域与 Windows 区域录屏仍未实现。
- 悬浮球：拖动、靠边停靠、记住位置、右键停用/仅今天停用/设置；菜单栏或托盘可恢复。当日停用按本地日期并在唤醒时复核。
- 空闲时不保持屏幕捕获流，不存储屏幕历史。OCR、编码器按需初始化。

## Chrome 配套入口

构建 `python3 scripts/build-chrome.py` 后，在 Chrome 开发者模式加载 `outputs/chrome/Snapliq for Chrome`，再在 Snapliq 设置中选择连接 Chrome。详见 [桥接说明](docs/chrome-bridge.md)。

扩展仅申请 nativeMessaging，没有屏幕捕获、常驻录制或远程脚本。提供截图、录屏和设置入口；回执“请求已发送”不代表图片或视频已完成。当前未提供 DOM 精细框选或整页滚动截图。扩展卸载后桌面核心继续工作。

## 源码和构建

| 目录 | 职责 |
|---|---|
| apps/macos | 原生生命周期、SCK 截图与录屏、AppKit 窗口、Vision、系统剪贴板/保存/AirDrop |
| apps/windows | Win32 窗口、WGC、Media Foundation、WASAPI、UIA、Windows OCR |
| core | C++20 几何、混合 DPI 坐标、选区与工具栏布局 |
| apps/bridge-macos、apps/chrome | 随应用打包的 Native Messaging 适配器及可选 MV3 入口 |
| brand/product.json | 名称、描述、标语和版本；发布身份与数据目录另行维护 |
| assets | 原创可编辑 SVG、深/浅图标、ICNS/ICO、菜单栏/托盘/悬浮球/扩展资源 |
| outputs/design-system/snapliq/MASTER.md | 使用 UI UX Pro Max 流程整理的桌面设计系统 |

macOS 需要 Xcode Command Line Tools、Python 3：
```sh
zsh scripts/build-macos.sh
zsh scripts/test-macos.sh
zsh scripts/test-services-macos.sh
open outputs/builds/0.2.2/Snapliq.app
```

默认构建输出 outputs/builds/<版本>/Snapliq.app，避免覆盖此前已授权版本。可用 SNAPLIQ_APP_PATH 指定另一输出位置。默认临时签名；重新构建可能使系统要求重新授权。SNAPLIQ_SIGNING_IDENTITY 可以指定已有签名证书，但脚本并未完成正式 hardened runtime、公证和发行流程。

Windows 需要 Visual Studio 2022 Desktop C++、Windows 11 SDK、CMake：
```powershell
./scripts/build-windows.ps1
# 安装 Inno Setup 6.3+ 后可生成开发安装器：
./scripts/build-windows.ps1 -Installer
```

GitHub Actions 构建配置已提供，当前未提交运行，不能替代 Windows 编译证据。图标可用 `python3 scripts/generate-assets.py` 重建。开发包与源码归档使用 `python3 scripts/package-development.py`，不会重签已构建应用。

交互回归会操作桌面和剪贴板，执行条件与命令见 [测试说明](docs/testing.md)。普通服务测试不测真实屏幕呈现延迟。

## 验收与发行边界

- 当前签名为 ad-hoc，无 Developer ID、公证、Windows 代码签名或商店发布。
- macOS 26+ 的 NSGlassEffectView 路径有 SDK 条件编译；本机 SDK 15.5 只构建并验证 NSVisualEffectView 降级。没有声称验证 macOS 27 新 API。
- Icon Composer 的角与点分层 SVG 已准备；**没有编译后的 .icon 资源**。现有应用用实际 ICNS，Windows 用静态 ICO。
- 多物理显示器、混合 DPI、全屏/Spaces、HDR/色彩还原、完整辅助技术访问、长时间录制及设备变化仍需专门实机验证。
- 来源窗口关闭后的原生录制模块封装与资源状态已验证；设备变化、休眠和撤权仍待实测。
- 本地 OCR 已验证；真实麦克风录制和 AirDrop 跨设备送达尚未验证。AirDrop 系统取消与临时文件清理已验证。
- 权限、签名与安装注意事项见 [权限和发行](docs/permissions-and-release.md)。

日志位于用户 Application Support/Snapliq Development/Diagnostics，仅记录事件、尺寸、计时与错误，不写屏幕像素。测试产生的桌面录像、个人剪贴板备份和浏览器截图不进入源码或交付证据包。
