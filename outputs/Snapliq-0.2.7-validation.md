# Snapliq 0.2.7 中英界面切换验收

日期：2026-11-19。当前范围：macOS 与 Windows 独立桌面应用；Chrome 商店提交保持暂缓。

## 行为

- 设置顶部「语言 / Language」支持「简体中文」和「English」，默认中文，保留语言选择。
- 设置、菜单栏／托盘、悬浮球、截图栏、OCR 结果、录屏来源／控制栏及应用自定义错误提供中英文字。
- 切换语言不重新注册快捷键，不取消当前选区，不覆盖 OCR 用户编辑文本，不重建录制会话。OCR 的中英识别能力与界面语言无关。
- 系统对话框和底层系统错误按操作系统语言显示。文件名、保存位置、发布身份和数据目录保持原值。

## 验证环境与边界

本机：MacBook Air M2（Mac14,2）、16 GB、macOS 15.6.1（24G90）、Command Line Tools SDK 15.5、arm64。测试使用生成图片，个人屏幕内容不上传。

没有真实 Windows 设备，Windows 云端编译和测试不代表 Windows 10/11 实机布局、音频设备或混合 DPI 验收。macOS 开发签名和 Windows 未签名发行边界与上一版一致。

## 已通过的验证

| 范围 | 结果 |
| --- | --- |
| macOS 编译与包 | 原生 arm64 构建、签名完整性检查、DMG 校验和 ZIP 打包通过 |
| 语言偏好 | 中文默认值、中英互换、真实子进程重启持久化、无效值回退、其他设置不变、主线程通知通过 |
| macOS 原生界面 | 实际设置下拉操作、同一窗口即时刷新、未完成快捷键录入保持且可取消、已有截图选区和遮罩保持、中英文工具栏按钮布局通过 |
| OCR 界面 | 生成图片的本地识别完成后，修改结果内容与选中文本，再切换两次语言；编辑内容与文本选区保持 |
| 录屏界面 | 暂停／录制控制状态的中英文显示保持；此项只验证控制界面，不启动真实录制流 |
| 常规 macOS 回归 | 1,972 个几何边界用例、原生图片处理、本地中英 OCR、MP4 封装与暂停时间轴、静态画面时长、桥接、智能候选缓存、44 项快捷录屏及 114 项悬浮球检查通过 |
| Windows CI | 4/4 CTest：1,972 个几何边界用例、2,422 项悬浮球、3,760 项原生图片与媒体检查、21 项实际 Win32 语言控件检查通过 |
| Windows 分发 | 原生编译、版本、便携包载荷哈希、安装器安装与卸载通过 |

最终构建来源：[Actions 44479055131](https://github.com/FIONN191/Snapliq/actions/runs/44479055131)，提交 `7000d53276627661a59b41958b771815f294d014`，两端任务均成功。首次云端验证 [Actions 44477619645](https://github.com/FIONN191/Snapliq/actions/runs/44477619645) 也通过；随后修正 macOS 可选界面测试脚本的 DesktopBridge 编译依赖和 OCR 测试样本匹配，应用生产源码未再变更。

## 本机已安装应用

`/Applications/Snapliq.app` 更新为 0.2.7，安装前确认无活动选区和打开的录屏文件，并保留旧版备份。直接操作已安装应用的语言下拉框，确认中文切英文后标题变为 `Snapliq Settings`，退出再打开仍为 English；隔离界面测试同时验证了切回中文。最终 CI ZIP 中的应用与本机安装包的 5 个文件逐字节一致。

更新后系统权限暂时失效，用户重新授权后，应用的实际启动日志报告 `screenPermission: true`。对同一安装包运行内置诊断：三次真实 ScreenCaptureKit 捕获均成功，单屏 1470×956 逻辑坐标／2940×1912 像素；原生 PNG 剪贴板往返、负坐标 Retina 裁剪和不覆盖保存均通过。剪贴板在测试后恢复。三次后台捕获仅为功能检查，不作为四项快捷键端到端 P50/P95 性能结论；未上传屏幕像素。

本轮未重新验证：真实录制流中切换语言、Windows 10/11 物理桌面和音频设备、多屏混合 DPI、正式签名与公证。

## GitHub 下载

[v0.2.7](https://github.com/FIONN191/Snapliq/releases/tag/v0.2.7) 已发布为 Latest，包含六个固定名称附件；首页 macOS 和 Windows 按钮继续使用 `/releases/latest/download/` 地址。两端包均来自最终 Actions 44479055131。

上传前后逐项比较大小与 SHA-256。发布后使用无账号、无授权头的请求重新下载六个固定地址，全部 HTTP 200，字节数和 SHA-256 均匹配；本轮无需 API 回退下载。

| 文件 | SHA-256 |
| --- | --- |
| Snapliq-macOS.dmg | `41ef9e9ca3988ea6a4254684ac575a8f67ee3f74374a5bf7d32b702a373e2299` |
| Snapliq-macOS.zip | `baf3abe46791a0d86f55d7cdf4526a1a37e7f864bcca8709fb82c82ca7a17240` |
| Snapliq-Windows-Setup.exe | `e11d5caad64cb73d354c8cae7bd58e3a50e0a1b4f961d1ee12e8c79130b3bc3e` |
| Snapliq-Windows-Portable.zip | `bcfcad982c9d73c0b63d5a968bdddd9c7a5d0bce07d9b1f7efd443fbf9e2b5cc` |

源码继续同步至 `FIONN191/Snapliq`。本次因原外置磁盘未挂载，使用 `/Users/fionn/Documents/Codex/Snapliq` 本地克隆完成开发；没有修改旧磁盘上的未挂载副本。安装包和本地测试中间文件不提交源码历史。
