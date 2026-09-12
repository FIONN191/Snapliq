# 权限、平台差异与开发分发

## macOS

| 能力 | 权限 / 系统入口 | 拒绝后的行为 |
|---|---|---|
| 桌面截图、屏幕/窗口录屏、系统声音 | 屏幕与系统音频录制；实际名称随系统版本变化 | 显示权限说明和设置入口，不将“已打开设置”报告为截图成功 |
| 窗口内控件识别 | 辅助功能，可选 | 退回窗口边界或手动选区；不阻断手动截图 |
| 麦克风 | 系统麦克风权限；本版 SCK 输入要求 macOS 15+ | 禁止未经授权的输入；macOS 14 不提供该选项 |
| 图片/视频保存 | 系统目录和保存面板、文件夹实际写权限 | 保留可重试状态并解释权限错误 |
| AirDrop | NSSharingService 系统分享流程 | 处理不可用、取消、错误及临时文件清理 |
| 登录启动 | ServiceManagement 系统管理 | 开关与实际注册结果同步 |

普通全局快捷键注册不需要把 Accessibility 当成截图权限；测试工具注入按键另外需要辅助功能授权。Command + X 与剪切存在真实冲突，默认候选需要明确接受，不能宣称同时无冲突执行。

当前开发应用未启用 App Sandbox，使用用户文件访问权限及保存面板。若后续发行采用沙盒，必须补齐 security-scoped bookmark、entitlement 和实际失效/重授权验证，不能沿用非沙盒验证结论。

临时签名变化可能造成 TCC 授权与新包不一致。保留当前已授权候选；不要通过直接编辑系统隐私数据库修复。必要时用户在系统设置重新授权新包。版本号不等于签名身份，单一 screenPermission 日志也不证明完整捕获成功。

## Windows

目标开发基线 Windows 10 2004+，建议 Windows 11 实测。Win32 宿主用 WGC；当前用户启动，manifest 为 asInvoker、PerMonitorV2。麦克风/桌面应用隐私开关及设备实际格式需检查；系统声音用 WASAPI loopback。受保护内容和安全桌面不能绕过。

自身捕获排除优先 WDA_EXCLUDEFROMCAPTURE；失败时控制条隐藏，托盘仍保留停止入口。UI Automation 不能保证访问提权或所有自绘应用，失败回退窗口边界。Windows 未编译和实测，版本和运行能力必须在目标机器确认。

## 发行状态

当前只交付开发包和源码。macOS Apple Silicon app 使用原有开发 bundle identifier 和数据目录；无 Developer ID、公证、hardened runtime 完整发布配置。Windows 安装器是 Inno Setup 源码，尚无已构建或签名安装包。

正式发布前：使用用户指定稳定身份，配置并检查签名/entitlement、公证与安装升级/卸载；在可用 Xcode/SDK 下构建 NSGlassEffectView 与 Icon Composer 资源；运行真实 macOS/Windows、多显示器和录制中断矩阵。不得因名称配置变化修改用户既有发布 ID、签名或数据位置。
