# Snapliq 0.2.3 — 快捷录屏验收

日期：2026-09-26。桌面功能增量；Chrome 发布继续暂缓。

## 已实现
- macOS 独立 Option+Command+R / Windows Ctrl+Alt+R；原生设置可修改，截图与录屏互斥校验，按下/释放去重复。
- 直接录制鼠标所在屏幕，再按同一快捷键停止并自动保存；准备和封装期间拒绝重复启动。
- 来源面板仍可选择窗口或 macOS 单屏区域，开始按钮移除提前保存对话框。
- 系统音频、麦克风默认开启，记住用户显式关闭；遵守麦克风权限，macOS 14 明示不支持麦克风。
- 沿用默认保存位置；无配置时使用 macOS Movies/Snapliq / Windows Videos/Snapliq。配置失效明确报错，自动命名、最终移动不覆盖既有文件。
- 主产品生命周期、截图 Command+X 设置和冲突确认、签名标识与数据目录保持既有配置。

## 当前机器
Apple M2 MacBook Air，16 GB，macOS 15.6.1 (24G90)，SDK 15.5，单屏。截图历史日志显示捕获像素 2560×1664；本轮未重测混合 DPI 或多物理显示器。

## 已实际通过
- `scripts/build-macos.sh`：原生 arm64 App 完整构建，临时签名及 codesign 严格验证通过。
- `scripts/test-quick-recording-macos.sh`：44 项；18 项偏好默认与迁移、17 项目录/书签/重名保护、9 项实际 Carbon handler 事件路由和长按抑制。未注册真实全局热键或请求屏幕、麦克风权限。
- `scripts/test-macos.sh`：1,972 个几何边界用例、权限失败传播、原生像素裁剪、负坐标/混合密度拼合、PNG 往返、10 次重名保存、临时文件清理。
- `scripts/test-services-macos.sh`：本地中英文 OCR、2 秒/60 帧 MP4 封装与暂停时间轴、8 秒静态画面尾帧、Native Messaging 与智能候选缓存回归。
- `scripts/test-region-recording-macos.sh`：750 个纯几何用例；本轮未用 `--run-interactive`。
- 独立 AppKit 设置探针：550×670 与 520×450 视口无约束歧义，可滚动，默认双音频勾选；快捷键录入 Esc 与关闭窗口均恢复两组回调。
- 0.2.3 已复制到 `/Applications/Snapliq.app` 并启动。实际进程日志记录截图与录屏两个全局快捷键 RegisterEventHotKey 均返回 0。

- DMG 经 `hdiutil verify` 校验通过，ZIP CRC 与版本校验通过；安装的 App、构建 App 和 ZIP 内可执行文件逐字节一致。

## 仍待实际交互验收
首次验证因系统锁屏无法操作；用户解锁后已实际检查 0.2.3 设置界面，确认两组快捷键独立开启、双音频选项勾选、已有 Documents 保存目录保留。新开发签名启动日志的 `screenPermission` 为 false，应用实际显示系统授权提示，需用户在系统隐私设置允许当前 Snapliq 后重启。不能将模块通过或注册成功当作最终 App 录屏成功。

需解锁/授权后验证：快捷键一次开始、再次停止、MP4 双音频输出、设置关闭后继续生效、声音手动关闭后重开仍保留、面板开始不出现保存对话框。本轮没有取得最终 App 的录屏时延 P50/P95。

GitHub Actions [36233655807](https://github.com/FIONN191/Snapliq/actions/runs/36233655807) 已完成，macOS 与 Windows 两项均成功，所验证的功能提交为 `db74ae535631d05566e5604330f523815d9133ec`。Windows 云端编译与共享测试通过；真实设备的热键、WASAPI 双音频、DPI 与权限交互仍未验收。当前包仍为开发临时签名，没有 Developer ID 公证；不宣称完成正式跨平台发行。
