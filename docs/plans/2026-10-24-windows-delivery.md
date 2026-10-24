# Windows 桌面交付 0.2.5

沿用用户此前确认的独立原生桌面架构。此次需求为可在 Windows 10/11 使用的实际程序，录制整个显示器上允许捕获的内容，切换应用和关闭 Chrome 不影响录制。

选择现有 Win32/C++/WinRT + Windows.Graphics.Capture，保留屏幕/窗口两种来源，Media Foundation 输出 H.264/AAC MP4，WASAPI 捕获系统声音与麦克风。无需重写为 Electron 或浏览器录制。Windows 10 最低为 2004/build 19041，既满足光标捕获 API 也支持排除录屏控制条；Windows 11 使用同一 x64 包。多显示器逐个选择，本次不加入多屏合成或区域视频裁剪。

交付 Inno Setup 每用户安装器和免安装 ZIP，静态链接 VC++ 运行库，保留 AppId、注册表偏好和安装目录。增加 PE 版本资源、安装器最低系统版本及应用运行时检查。系统权限和保护限制不绕过；N/KN 缺少媒体组件时给出明确恢复提示。

验证分层：本机可移植逻辑测试；GitHub Windows 原生编译/CTest；生产图片处理的生成输入测试；如可复用生产编码路径则编码/解码非对称测试帧；安装器静默安装到临时目录、验证文件版本/哈希、卸载。云端测试不能替代 Win10/11 实机录屏、设备和多屏验证，交付文档明确范围。

原移动盘初始未挂载，随后用户已挂载，继续在原仓库工作。无 Chrome 商店提交，不变更 macOS 安装或授权。

官方版本依据：
- https://learn.microsoft.com/en-us/windows/win32/api/windows.graphics.capture.interop/nf-windows-graphics-capture-interop-igraphicscaptureiteminterop-createformonitor
- https://learn.microsoft.com/en-us/uwp/api/windows.graphics.capture.graphicscapturesession.iscursorcaptureenabled
- https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity
