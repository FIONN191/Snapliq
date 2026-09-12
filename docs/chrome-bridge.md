# Snapliq for Chrome 与桌面桥接

桌面应用拥有生命周期。Chrome 仅启动随桌面包提供的标准输入输出适配器，适配器向已运行的桌面宿主发送请求；非 ping 请求可启动已安装桌面宿主。Chrome 关闭、适配器标准输入 EOF、扩展卸载都不会结束桌面进程或录屏。

开发扩展 ID：kfelibejienomlbgeeeebdieplppclcc，由 config/chrome-development.json 中公开开发密钥固定。正式商店身份另行确定，不要自动迁移既有身份。

## 安装

1. 保持 Snapliq.app 在稳定目录，启动应用。
2. Chrome 打开 chrome://extensions，开发者模式加载 outputs/chrome/Snapliq for Chrome。
3. 在 Snapliq 设置选择「连接 Snapliq for Chrome…」。此时应用只为当前用户注册 Native Messaging host。
4. 打开扩展，显示桌面版本与连接状态；截图、录屏和设置均由桌面处理。

macOS host 注册文件位于 ~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.snapliq.desktop.development.json，指向应用包内 Contents/MacOS/SnapliqBridge。
Windows 使用当前用户 NativeMessagingHosts 注册表项；入口由桌面可执行文件提供。
移动应用后，在新位置重新执行连接即可。删除扩展不会删除用户图片、录屏或应用设置。

## 协议与边界

请求 action 仅允许 ping / capture / record / settings；JSON 使用标准四字节小端长度前缀。最大请求 64 KiB。回复只确认桌面接收请求，完成状态仍由原生窗口展示。

macOS 本地 socket 目录 0700、端点 0600，并验证同一 UID；Windows 命名管道限制当前用户 SID 和本地客户端。桌面读超时防止单个空闲客户端无限占用。Chrome host 校验固定的 chrome-extension 来源。没有任意命令执行、任意文件读取、浏览器截图或屏幕图像回传 API。

扩展只有 nativeMessaging 权限、严格本地 CSP，无 service worker、内容脚本、远程 JS 或 WebAssembly。当前不包含 DOM 边界增强；未来新增时仍必须保持桌面捕获和权限独立。

测试包含协议 action 白名单、帧长限制、超时、端点权限、来源拒绝和 EOF 后桌面存活。macOS 已通过真实 Chrome 加载并验证连接及打开设置。Windows 桥接仅完成源码，等待 Windows 验证。
