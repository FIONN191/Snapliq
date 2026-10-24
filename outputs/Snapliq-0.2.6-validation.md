# Snapliq 0.2.6 — OCR 后结束截图

日期：2026-10-24。修复提交：`b8186a1555f9513f8795a22fe089c0643779f140`。

## 行为

- 两端先复制当前选区像素，再结束截图和释放桌面底图；不等待 OCR 完成才退出选区。
- macOS 的文字结果由独立 OCRController 管理，关闭截图不会释放文字窗口。关闭结果不再恢复遮罩。
- Windows 复用结果窗口，最多一个活动识别和一个最新待处理请求；关闭时清理待处理请求，过期识别结果不能覆盖新结果。
- OCR 结果窗口打开时，仍可启动新截图。图片裁剪失败时仍保留选区并提示错误。

## 本地验证

设备：Apple M2，macOS 15.6.1（24G90），SDK 15.5；单屏逻辑 1470×956，Retina 底图 2940×1912。

- `scripts/test-macos.sh`：1,972 个核心几何边界检查、负坐标、混合密度合成、PNG、重名保存和清理通过。
- `scripts/test-selection-ui-macos.sh --run-interactive`：使用生成的中英文底图执行真实 AppKit/Vision 流程，验证提取后完成回调执行、会话释放、遮罩和两条工具栏关闭；文字仍可编辑/复制；结果未关闭时可再次截图并复制真实 PNG；关闭 OCR 不恢复选区；提前关闭后不重新出现窗口。测试结束恢复剪贴板。
- 独立代码审核检查了应用层对 OCR 窗口的持有、异步回调、截图重入和关闭路径。
- 本机 `/Applications/Snapliq.app` 已更新为 0.2.6，原 0.2.4 备份保留在本地 `outputs/installed-backups/`。签名完整性检查通过。用户重新授权后，最终应用成功获取实际桌面底图并进入选区；本报告的完整 OCR 操作验证来自上述原生 UI 回归程序，不将其混同为最终应用的完整自动化验收。

## 云端验证

[GitHub Actions 40075859590](https://github.com/FIONN191/Snapliq/actions/runs/40075859590) 的 macOS 和 Windows 均成功，对应上述修复提交。Windows 构建脚本包含三个 CTest 目标、原生图片/MP4 编码解码，以及安装器安装、版本/哈希与卸载检查。

## 发布检查

[v0.2.6](https://github.com/FIONN191/Snapliq/releases/tag/v0.2.6) 已发布并设为 Latest，仓库首页固定下载按钮对应此版本。六个附件上传后的大小和 GitHub SHA-256 均与成功 CI 产物一致。

本地直连 github.com 下载入口出现连接超时，因此改用无需登录的 GitHub 官方 Release 文件接口，实际取回六个附件；全部 HTTP 200，SHA-256 与原始文件一致。公开 Latest 元数据与四个 browser_download_url 也已核对。本轮没有把直连超时记作按钮下载测试通过。

- `README-Windows.zh-CN.txt`：`28d3758c5f15610c3f5dc08458b4d87679ecbbc07b4226ce5bebe52efe96a6df`
- `SHA256SUMS.txt`：`2178b207379304253f23ad3187f253936303883fb0a9e40eb90b19c8781a8e15`
- `Snapliq-macOS.dmg`：`303f7309c951e967467c9e449a87bb1ba688103115c03905298ebe4ee0b046e3`
- `Snapliq-macOS.zip`：`6c260dff15f33636efcbd4129d9caf303ba2cf9104e67de3d41c99876bf3ae98`
- `Snapliq-Windows-Portable.zip`：`82b1e5600df6fa72dacdf04e041af3b238269e28b5b82812be9ca8c6ab310116`
- `Snapliq-Windows-Setup.exe`：`851157b062130c79c9be46776738f9c4f32aa908b6450e1ef6a5db625ec9dff4`

## 边界

没有 Windows 10/11 实机 OCR UI 或真实捕获/音频设备结论；没有新增性能 P50/P95。此前未验收的混合 DPI、设备变化、长时录制、正式签名/公证等边界保持不变，见 [0.2.5 验收](Snapliq-0.2.5-validation.md)。
