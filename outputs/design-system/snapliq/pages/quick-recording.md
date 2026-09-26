# 快捷录屏 · 0.2.3

2026-09-26，按用户明确请求，沿用已确认的原生桌面架构。

## 本次 Skill 流程
实际运行 `npx --yes --package uipro-cli uipro init --ai codex`，安装到 `.codex/skills/ui-ux-pro-max`，读取其 SKILL.md。
执行 design-system（native desktop productivity screen recording keyboard shortcuts monochrome minimal accessible settings）、UX（keyboard shortcuts state feedback permission loading）、swiftui stack（settings accessibility state）查询。
自动生成结果含营销 CTA、Vibrant Blocks 和网络字体，均不适用于此原生生产力工具，因此继续采用 MASTER 的黑白银灰、系统字体、原生控件。本页记录筛选后的实施规则。

## 行为与可访问性
- 截图与录屏各有启用开关和快捷键录入按钮，拒绝相同组合；保留 Command+X 剪切冲突提示。
- macOS 录屏默认 Option+Command+R；Windows 默认 Ctrl+Alt+R。直接录制鼠标所在屏幕，再按一次结束并保存。长按不重复触发；准备和保存期间忽略再入。
- 窗口和区域来源仍在录屏面板选择，点击“开始录制”后直接录制，不再先开保存对话框。
- 系统声音与麦克风默认开启；用户关闭后持久化，不能在每次开始时强制重开。macOS 14 明示麦克风需要 macOS 15+。
- 首次系统权限必须遵守 OS 授权，拒绝时解释原因，不静默改成无声录屏。
- 状态文字区分“正在准备”“录制中”“已暂停”“正在保存”；使用计时和按钮状态，不仅依赖颜色。
- 设置可滚动/调整大小，保持原生键盘焦点、可访问性标签、减少透明度与减少动态效果适配。
- 保存目录：沿用用户默认文件夹，否则 macOS 影片/Snapliq、Windows 视频/Snapliq；失效的自选目录报错。自动文件名避免冲突，封装完成后不覆盖其他文件。
- 最近录屏可从菜单栏在 Finder 中显示。所有录屏状态来自桌面原生进程，无浏览器依赖。
