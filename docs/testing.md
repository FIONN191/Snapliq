# 测试与证据口径

普通检查：先运行 zsh scripts/test-macos.sh，再运行 zsh scripts/test-services-macos.sh。前者编译共享几何与原生图片处理测试；后者验证本地 OCR、视频暂停/静态时长、桥接和扩展协议。测试不重建或重签当前运行应用。

交互性能测试会覆盖桌面、移动鼠标、注入 Command + X / Enter / Esc 并临时改写剪贴板。必须在无人操作时主动运行；不要加入常规 CI。测试将保存并恢复当前剪贴板、退出自身创建的测试窗口，失败时也执行清理。强行结束进程或断电无法保证 finally 执行，输出目录中的 clipboard-backup.plist 可通过 ClipboardPreserve 恢复；该文件包含用户数据，不应上传。

条件：已授权且运行的候选 App、接受并启用 Command + X、测试工具拥有辅助功能权限、Chrome 完全退出。请先完成任何浏览器未保存工作。脚本不会自动退出 Chrome 或改变系统权限。

本次设备单屏逻辑 1470×956、导出 2940×1912。重现命令：
```sh
python3 scripts/benchmark-interactive-macos.py --run-interactive --samples 100 \
  --configuration "MacBook Air M2 16GB; macOS 15.7.7; 1470x956 logical / 2940x1912 capture; 60Hz"
```
换设备需调整 --crop x1 y1 x2 y2、--expected-pixels width height 和配置描述。不能把示例尺寸硬套到其他屏幕。确认测试前有没有运行录屏或打开选区；不要影响用户进行中的任务。

TimedKey 在 CGEvent key-down 提交前记录 systemUptime，与应用日志的同一单调时钟比较。四项为触发→反馈提交、触发→干净底图、触发→选区可用事件、Enter 提交→PNG 写入完成。包括 OS 分发与主线程调度。此方法不测物理键盘扫描、显示合成器真正呈现或光子延迟；后两者需要额外呈现探针或高速摄影。保留首样本，P50/P95 用线性插值。

tests/macos/SelectionUITests.swift 使用生成底图执行真实 AppKit OCR 编辑/复制与选区恢复；AirDropSmoke.swift 只用于系统分享取消清理检查，测试中不能选择实际接收设备。LiveRecordingTests.swift 使用真实系统捕获，录下的桌面/系统声音可能涉及用户内容，应仅保留本地，不纳入源码包。测试程序不是最终应用权限身份的替代品。

Windows：已有 CMake 与 PowerShell 构建/核心测试配置。尚无 Windows 机器，所以没有编译、媒体解码、方向、混合 DPI、音频设备、控制条排除或 UIA 的运行结论。首次 Windows 验证应先编译、截图真实 PNG/剪贴板，再做短屏幕/窗口 MP4 解码、暂停与声音，最后做多屏及异常停止。

WindowClosureTests.swift 使用真实 SCK 独立窗口来源，关闭自身创建的测试窗口，检查停止回调、文件封装、时长与 idle 状态；该模块测试已通过，最终 UI 的更多来源类型仍应覆盖。

正式验收仍需：多物理屏幕/混合 DPI、全屏和 Spaces、真实 AX/UIA 控件命中、麦克风输入、更多窗口类型/休眠/设备变化/权限撤销、小时级录制资源走势、macOS 26/27 材质、跨设备 AirDrop、签名公证及升级安装。已有单屏通过项不能推断这些通过。

## 0.2.1 native interaction checks
Noninteractive latest-pointer/caching tests are included in scripts/test-services-macos.sh. Opt in to actual native controls with `zsh scripts/test-native-interactive-macos.sh --run-interactive smart` or `--run-interactive recording`. The smart test briefly moves and restores the pointer and verifies a native button behind its own overlay. The recording test operates a generated window and saves a local MP4; it uses AXPress on stable control identifiers. These helpers do not inherit or prove the final app bundle TCC authorization. The recording harness runs the real NSApplication event loop, which is necessary for reliable external AX delivery.

## 0.2.2 macOS desktop region recording
`zsh scripts/test-region-recording-macos.sh` runs geometry validation. `--run-interactive` additionally creates a generated native four-color window and a host overlay, records an asymmetric crop through the real ScreenCaptureKit/encoder modules, verifies decoded color probes and dimensions, checks pause/resume/finalization and full ffmpeg decode, then tests the native region-selection UI. These module hosts have separate TCC identities from the final App. The installed SDK states sourceRect is in display logical points and destinationRect is in pixels. Region recording currently supports a single display on macOS; cross-display video and Windows region video are not implemented.

Desktop-only delivery: `zsh scripts/build-macos.sh`, then `zsh scripts/package-macos-dmg.sh`, then `python3 scripts/package-development.py --desktop-only`. This builds the versioned app and DMG/ZIP without rebuilding or submitting the Chrome companion. Do not overwrite the authorized 0.2.1 app.
