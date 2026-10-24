# Snapliq 0.2.5 — Windows 桌面包验收

日期：2026-10-24。目标：Windows 10 2004（build 19041）及以上 / Windows 11，x64 独立桌面截图与录屏程序。

## 本次交付行为

- Windows.Graphics.Capture 录制整块显示器或单个窗口。整个显示器模式覆盖桌面、浏览器和普通软件之间的切换；Chrome 不参与应用生命周期或捕获。
- Ctrl+Alt+R 直接开始录制鼠标所在显示器，再按一次停止并自动保存。默认系统声音与麦克风开启，保留用户显式关闭选择。默认保存到“视频/Snapliq”，已有默认目录继续使用。
- MP4 为 H.264 视频及可选 AAC 声音。关闭设置不退出工具；托盘保留暂停/继续/停止。控制条与悬浮球优先排除捕获，排除失败时隐藏；打开正在录制的控制条也重新检查排除结果。
- 安装器与应用入口统一限制 Windows 10 build 19041+。静态链接 VC++ 运行库，增加实际 PE 文件版本资源。每用户安装位置、AppId、偏好位置保持不变。
- 停止录制时，清理捕获流或音频尾部失败不会直接跳过 MP4 Finalize；保留具体错误。修复 480 个音频采样乘以 10,000,000 时的 32 位溢出，现为准确的 100,000 个媒体时钟单位（48 kHz 下 10 ms）。编译器 C4307 升级为错误。

## 验证方法与范围

本机为 macOS，只运行可移植 C++ 检查：1,972 个核心几何边界与 2,422 个 Windows 悬浮球布局检查通过。Windows 原生构建使用 GitHub Actions 的 Windows Server 2025 x64 runner，与 Windows 10/11 实机验证区分。

Windows 原生测试调用生产代码而非模拟实现：

- `capture.cpp` 的像素裁剪、PNG 编码、文件保存；WIC 解码验证方向、通道、透明度与像素，覆盖中文路径、重名拒绝覆盖、显式覆盖、不可用目录和临时文件清理。
- `recorder-video.h` 的实际 H.264 编码与 MP4 封装；生成带行填充、非对称分区的图案，再实际解码检查四角颜色/方向、尺寸、时间戳、文件结尾和两秒静止画面尾帧。
- 时间换算编译期断言和 562,581 次可移植比较，覆盖音频块、秒和长时换算；这不等于真实声音设备验收。
- 安装器静默安装到 CI 随机临时目录，核对版本与程序 SHA-256，正常卸载并确认程序文件消失；仅在干净 CI 中运行，不操作开发机已安装副本。
- 免安装 ZIP 内的程序与原编译 EXE 逐字节一致，附中文使用说明；下载后独立校验 SHA-256、ZIP CRC、PE x64 架构及运行库导入。

## 最终构建和下载验证

GitHub Actions [40073913026](https://github.com/FIONN191/Snapliq/actions/runs/40073913026) 验证提交 `af67b8edacceb7e2be1d5dfee5e62a357920bab0`，macOS 和 Windows 均成功。Windows 三个 CTest 目标全部通过：核心几何、2,422 个悬浮球布局检查、3,760 个原生图片/编码断言。实际 MP4 解码取得 60 帧，非对称画面与两秒静止结束时长通过；最终编译日志没有 C4307 溢出告警。

安装器的安装、版本/哈希验证与卸载已通过。取回的最终 EXE 确认为 x64 PE，没有外部 VCRUNTIME/MSVCP DLL 依赖；ZIP CRC 和所有 SHA-256 已独立核对。公开下载见 [v0.2.5 Release](https://github.com/FIONN191/Snapliq/releases/tag/v0.2.5)，无需登录 GitHub；[原始 CI 产物](https://github.com/FIONN191/Snapliq/actions/runs/40073913026/artifacts/12552198293) 另行保留。本地交付在 `outputs/windows/0.2.5/`。

- `Snapliq.exe`：`89384497234c81a7763609f6a772395438762544a26276a034dcdc4f3899dac3`
- `README.zh-CN.txt`：`951cc8b6530f90422d6055f79bf6fdd3f2336ecfdfdfe56fff3be31cfe8ba83e`
- `Snapliq-0.2.5-windows-x64-development-portable.zip`：`6800438f6efebf4d13b5af3b1f7a5c70791c856704b03d2fa6ecb35613b2f543`
- `Snapliq-0.2.5-windows-x64-development-setup.exe`：`c44cbf759b23ad909a3e80f851afcc28cf944b08e217251fa385cc61d6b23245`

## 两端公开发布检查

2026-10-24 将同一成功 CI 运行中的 macOS 和 Windows 包发布为 v0.2.5，标签指向已测试提交 `af67b8edacceb7e2be1d5dfee5e62a357920bab0`。固定下载文件名仅为复制后的重命名，二进制内容保持一致。macOS 应用版本为 0.2.5、arm64、最低 macOS 14；`codesign --verify --deep --strict`、DMG 完整性和 ZIP CRC 通过。该检查仅验证临时签名的完整性，不代表 Developer ID 签名或公证。

- `Snapliq-macOS.dmg`：`3c8a6e98cf7453947f7074903661e1ac9023de0e9d44b494f2d3f6c903ce8719`
- `Snapliq-macOS.zip`：`35bf1630b0cc05aa25a602ed032b2642fed7d66c48db68ce2889ce179067b32b`
- `Snapliq-Windows-Setup.exe`、`Snapliq-Windows-Portable.zip` 与上方版本化 Windows 原文件哈希相同。

发布后，不带 GitHub 账号、授权头或 Cookie，实际取回 `releases/latest/download/` 下的四个安装包／ZIP、Windows 使用说明和 SHA256SUMS.txt。六个地址均返回 HTTP 200，下载后的 SHA-256 全部与本地及 GitHub 附件一致。仓库首页提供两端下载按钮和 ZIP 入口；维护步骤见 [GitHub 下载与发布](../docs/github-releases.md)。

## 尚未通过实机验收的部分

此轮未连接 Windows 10/11 实机，不声称实测通过全局快捷键、真实 WGC 画面、WASAPI 系统声音/麦克风、混合 DPI、多显示器、睡眠/设备拔插或长时间录制。没有新的性能 P50/P95。

系统禁止捕获的内容（DRM、主动排除窗口、锁屏、UAC 安全桌面，以及部分独占全屏/特殊图形内容）不能保证录制。多显示器当前选择一块录制，不是多屏合成为一个视频；Windows 区域视频裁剪未实现。HDR 转 SDR 颜色还需实机验收。

Windows N/KN 必须在启动前安装 Media Feature Pack，缺少媒体 DLL 可能被系统加载器直接阻止；Windows ARM64 模拟运行尚未验收。当前安装器未做 Windows 代码签名，不作为完成正式发行认证的证据。本轮未替换本机 macOS App。
