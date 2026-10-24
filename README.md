# Snapliq

[![下载 Snapliq macOS 版，Apple Silicon，DMG 安装包](assets/download-macos.svg)](https://github.com/FIONN191/Snapliq/releases/latest/download/Snapliq-macOS.dmg)
[![下载 Snapliq Windows 版，x64，EXE 安装包](assets/download-windows.svg)](https://github.com/FIONN191/Snapliq/releases/latest/download/Snapliq-Windows-Setup.exe)

[macOS ZIP](https://github.com/FIONN191/Snapliq/releases/latest/download/Snapliq-macOS.zip) · [Windows 免安装 ZIP](https://github.com/FIONN191/Snapliq/releases/latest/download/Snapliq-Windows-Portable.zip) · [版本说明与校验文件](https://github.com/FIONN191/Snapliq/releases/latest)

macOS：Apple Silicon，macOS 14+；Windows：x64，Windows 10 2004／19041+ 或 Windows 11。当前为开发版：macOS 使用临时签名、尚未公证，Windows 尚未代码签名；实机验收范围见下文。下载按钮始终指向最新发布版本。

Capture. Record. Share. — 截图与录屏工具

Snapliq 是独立原生桌面应用。macOS 使用 Swift/AppKit + ScreenCaptureKit，Windows 使用 Win32/C++/WinRT + Windows.Graphics.Capture，两端共享 C++20 几何和布局核心。Snapliq for Chrome 仅提供配套入口；退出 Chrome、断开 Native Messaging 或关闭设置不结束桌面应用。

当前桌面开发版本 **0.2.6**：面向 Windows 10 2004（build 19041）及以上、Windows 11 的 x64 桌面安装器和免安装 ZIP。Windows 使用 **Ctrl+Alt+R** 直接录制鼠标所在显示器，再按一次停止并自动保存。整个屏幕包含桌面、浏览器和其他普通应用；切换应用或退出 Chrome 不会停止录制。系统保护或禁止捕获的内容除外。Windows 实际桌面、音频与混合 DPI 仍待实机验收，构建和安装检查单独记录。Chrome 开发与商店提交暂缓。

## 启动与使用

使用标题下方的按钮下载当前版本，其他版本见 [发布历史](https://github.com/FIONN191/Snapliq/releases)。安装包作为 Release 附件发布；本仓库跟踪源码、品牌资产和验收证据，个人视频与剪贴板备份不进入 Git 历史。本次修复与验证见 [OCR 后退出截图验收](outputs/Snapliq-0.2.6-validation.md)。其他验证范围见 [Windows 构建与安装验收](outputs/Snapliq-0.2.5-validation.md) 和 [macOS 悬浮球验收](outputs/Snapliq-0.2.4-validation.md)。

Windows 安装版运行下载的安装器；免安装版解压整个文件夹再运行 `Snapliq.exe`，无需 Chrome 或额外的 VC++ 运行库。完整操作说明见 [Windows 使用指南](packaging/windows/README.zh-CN.txt)。从源码构建的版本化安装器和 ZIP 位于 `outputs/windows/`。

macOS 下载 DMG 后，将 Snapliq.app 拖入“应用程序”。当前构建要求 macOS 14+、Apple Silicon；麦克风需要 macOS 15+。历史签名的权限与测试结论不自动沿用到新构建，升级后可能需要重新授权。不要同时启动两份开发应用。从源码构建的应用位于 `outputs/builds/0.2.6/Snapliq.app`。

首次截图需要系统屏幕录制权限。Command + X 是默认候选，只有用户接受普通剪切冲突后才启用；注册成功不代表它与剪切兼容。设置中可以直接修改快捷键。菜单栏、独立悬浮球与 Chrome 配套入口都可唤醒截图。关闭设置后继续常驻；选择「退出 Snapliq」才结束后台运行。

- 区域截图：拖动框选、移动和八点调整，显示导出像素尺寸。Enter/完成复制真实 PNG，Esc 取消，Command + C 复制，Command + S 保存。方向键移动，Option + 方向键调尺寸，Shift 加速，H 暂时隐藏底部栏。
- 下载菜单：保存、另存为、默认目录系统选择器；重名自动处理，权限失败保留选区并提示。
- 智能框选：先匹配系统窗口边界；可选 Accessibility/UI Automation 控件识别，失败退回窗口。窗口截图当前基于可见桌面区域，不恢复被遮挡内容。
- 提取文字：本地识别中文和英文。点击后立即退出截图选区和遮罩，仅保留可编辑结果窗口；关闭结果不会重新进入截图，结果窗口打开时也可再次唤醒截图。支持复制文本。macOS 使用 Vision；Windows 使用已安装的系统 OCR 语言包。
- AirDrop：macOS 直接进入系统分享服务，由用户选择接收设备。Windows 不显示 AirDrop。
- 录屏：原生屏幕/窗口来源、开始/暂停/继续/停止、时长、默认开启系统声音和麦克风（记住用户关闭的选择）。macOS 15+ 提供 SCK 麦克风输入，macOS 14 禁用该选项。保存 H.264/AAC MP4，暂停时间从时间轴扣除。macOS 0.2.2 支持单显示器内的真实区域视频裁剪：点击“框选录制区域…”，Enter 确认区域，点击“开始录制”。快捷录屏和来源面板均自动保存至默认目录；未设置目录时使用 macOS `~/Movies/Snapliq` / Windows `Videos/Snapliq`，无保存对话框。跨屏区域与 Windows 区域录屏仍未实现。
- 悬浮球：设置中可开关「吸附屏幕边缘」、调节 32–96 大小（macOS pt / Windows DIP，默认 48）并「锁定当前位置」。开启吸附时拖动结束停靠到最近的四边之一；关闭后保留自由位置。锁定限制拖动，点击截图和右键菜单仍可使用；也可直接右键锁定/解锁。记住尺寸、偏好、显示器和相对位置，显示器断开时回到可见屏幕。右键可停用或仅今天停用，菜单栏/托盘可恢复；修改大小不会使已隐藏的悬浮球重新出现。
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
zsh scripts/test-quick-recording-macos.sh
zsh scripts/test-orb-macos.sh
open outputs/builds/0.2.6/Snapliq.app
```

默认构建输出 outputs/builds/<版本>/Snapliq.app，避免覆盖此前已授权版本。可用 SNAPLIQ_APP_PATH 指定另一输出位置。默认临时签名；重新构建可能使系统要求重新授权。SNAPLIQ_SIGNING_IDENTITY 可以指定已有签名证书，但脚本并未完成正式 hardened runtime、公证和发行流程。

仅从源码构建 Windows 时需要 Visual Studio 2022 Desktop C++、Windows 10/11 SDK、CMake（SDK 版本不等于最低运行系统版本）：
```powershell
./scripts/build-windows.ps1
# 安装 Inno Setup 6.3+ 后可生成开发安装器：
./scripts/build-windows.ps1 -Installer
```

GitHub Actions 会构建两端并运行几何、快捷录屏、悬浮球与 Windows 原生图片/编码测试。Windows 流程还生成安装器和免安装 ZIP，验证版本和载荷哈希，在临时目录静默安装并卸载。通过云端 Windows 编译不代表实际桌面、声音或混合 DPI 验收通过。图标可用 `python3 scripts/generate-assets.py` 重建。开发包与源码归档使用 `python3 scripts/package-development.py`，不会重签已构建应用。

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
