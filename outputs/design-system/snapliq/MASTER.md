# Snapliq 项目设计系统
状态：0.2.1 开发候选设计系统；2026-09-08 更新。平面与平台图标已生成并接入构建；新系统原生玻璃与 Icon Composer 编译资源仍待目标 SDK 验证。
适用对象：原生 macOS / Windows 桌面生产力工具及其配套 Chrome 扩展。
此文件是项目设计规则的主文档；位于 outputs 内便于审阅，实施时由工程明确引用，不再沿用 Skill 原始营销模板。

## Skill 使用与人工筛选
来源：https://github.com/nextlevelbuilder/ui-ux-pro-max-skill
检查的仓库 main SHA：f3ac195224eac1eb0dfe1a3059c2a6add78ffbe3。
安装命令：npm_config_cache="$PWD/work/npm-cache" npx --yes --package ui-ux-pro-max-cli uipro init --ai codex
实装版本 ui-ux-pro-max-cli 2.15.0；当前 Codex 路径为 .agents/skills/ui-ux-pro-max，已实际读取 SKILL.md。
已执行需求分析 → design-system 查询 → 窄化重试 → UX/SwiftUI/WinUI/style 定向查询 → 平台适用性审查 → 本规范。
首次 desktop capture productivity minimal 返回 Product Demo + Features、青绿色和 Google Fonts；与需求不合，不采纳。
按 Skill 要求仅重试一次 desktop utility monochrome，得到可用的几何/留白/黑白基调，但仍夹带 Hero/CTA、蓝色和网页字体，不作为已验证桌面布局保存。
采纳：清晰层级、键盘可达、语义标签、对比度、减少动态效果、高对比系统主题。
覆盖：营销页、移动端导航、Google Fonts 网络加载、CSS blur 作为 macOS 原生材质、截图唤醒等待动画、现成品牌图标。
glassmorphism 数据条目的低成本标签不能用于实际 GPU 性能结论；性能以实机测量为准。
由于两次自动输出仍包含错误产品类型，没有直接 --persist 原始推荐；本 MASTER 为筛选后人工编写的持久化结果。

## 1. 命名和发布身份
desktopDisplayName：Snapliq
extensionDisplayName：Snapliq for Chrome
pronunciation：snap-lik
descriptionZh：截图与录屏工具
taglineEn：Capture. Record. Share.
概念：Snap + Liquid。
实施时集中于 brand/product.json 的显示层配置，并从中生成两端本地化资源和扩展名称。
bundleIdentifier、Team ID、Windows package identity、扩展 ID、数据目录名称分别维护，不能随着品牌显示名称修改而自动迁移。
桌面图标内部不加文字；Chrome 资源不加 Chrome 标识或 Extension 字样。

## 2. 原创几何符号
母版坐标系 64×64，正面、无透视，视觉中心 (32,32)。
上左 L 中心线：(14,34) → (14,14) → (34,14)。
下右 L 中心线：(30,50) → (50,50) → (50,30)。
两角具有 180° 对角呼应关系，保持右上/左下的开口；不是四角扫描框，不补闭合连线。
母版等宽笔画 6.5，统一圆角与圆头；32 px 及以下的栅格版采用母版单位 7.2 的笔画和 8.2 的点径，避免机械缩小导致断笔。
独立圆点直径 7.2，中心 (32,32)，不与角连接，静态品牌点与符号同色。
外轮廓约从 10.75 到 53.25，给整体约 10.75 单位边距；应用容器中可再按官方图标网格调整。
最小外部净空不少于一倍笔画；任何状态徽记单独附着在容器上，不改变母版 L 角。
可编辑源保留 stroke 母版，平台投产另导出 outlined path，便于 Icon Composer/图标引擎处理。
交付黑版 #000000 / 白版 #FFFFFF，同一几何结构；材质验证前优先判断纯平轮廓。

## 3. 小尺寸光学校正
| 尺寸 | 初始笔画 / 点径 | 检查重点 |
|---|---|---|
| 16 px | 1.75–2 / 2–2.25 px | 点不能消失，折角开口保持；按实际栅格对齐 |
| 24 px | 2.5–2.75 / 3 px | 两角同重、无接缝、与系统托盘视觉一致 |
| 32 px | 3.25–3.5 / 3.75 px | 留白清楚，避免圆点显得大于笔画节奏 |
| 64 px | 母版 6.5 / 7.2 px | 比例和统一端点成立 |
| 256–1024 px | 比例缩放，容器独立 | 玻璃高光不能吃掉开放边界 |
上表为设计目标。当前实际导出在 32 px 及以下使用笔画 7.2/64 × 尺寸、点径 8.2/64 × 尺寸；更大尺寸使用 6.5/64 和 7.2/64。已检查 16/24/32/64 px 在黑白背景上的联系表，保留开口及独立中心点；Windows 真实托盘仍待验收。
菜单栏/托盘/扩展各有光学校正版；黑白背景并排检查，系统真实工具栏再验收。
菜单栏使用 template 图像/向量，Windows 图标按系统 DPI 提供；录制与暂停在菜单文字/形状上区分，不只靠红/黄颜色。

## 4. 色彩与文字
| Token | 浅色 | 深色 |
|---|---|---|
| surface.solid | #F3F4F5 | #191A1C |
| surface.raised | #FFFFFF | #242629 |
| text.primary | #1B1D20 | #F5F6F7 |
| text.secondary | #555B63 | #B8BEC6 |
| symbol.primary | #17191C | #F1F3F5 |
| stroke.control | #747B84 | #89919C |
| focus | 系统强调色 / 高对比描边 | 系统强调色 / 高对比描边 |
默认品牌仅黑白银灰；系统强调色只用于明确焦点/选区交互，错误与录制状态可用语义色并配形状和文本。
不做紫蓝渐变、彩虹镀铬、霓虹、塑料、大块厚玻璃、过曝高光。
macOS 使用系统字体及中文回退，Windows 使用系统 UI 字体及中文回退；无网络字体依赖。
工具栏文字初始 13–14 pt/DIP，设置正文 14–15 pt/DIP；按平台系统可读性和用户字号验证，不机械使用移动端 16 px 规则。
常规文字对比目标 ≥4.5:1，有意义图标/边界 ≥3:1；透明材质必须测合成结果，不能只测 token 色值。
尺寸与时长使用等宽数字，避免变化时抖动。高对比模式使用系统语义颜色。

## 5. 四类品牌载体
A 应用图标：macOS 分层背景/捕捉角/捕捉点，Icon Composer .icon 与旧系统 AppIcon/icns；系统遮罩与材质不重复烘焙。
Windows 深/浅静态 .ico（含 16/24/32/48/64/128/256）与安装资源，外观和符号一致。
B 悬浮球：圆形玻璃容器，直接置入品牌符号；初始 48 pt/DIP、内部符号 25–27，不嵌入方形应用图标。
C 菜单栏/托盘：纯几何、高对比、无玻璃阴影，适配实际菜单栏 1×/2× 和 Windows DPI 尺寸。
D Chrome：沿用符号，工具栏 PNG 16/24/32 与 manifest 16/32/48/128；1×/2× 外观分别验证。
前景、背景、材质参数独立组织，保留可编辑矢量源。Windows 静态效果导出也应能从源文件再生成。
实施时必须接入 bundle/EXE/安装器/扩展构建，测试最终安装包资源，而非只展示设置预览。

## 6. 材质与状态
使用 SDK 26+ 构建时启用 NSGlassEffectView，并做 macOS 26 运行时检查；控制内容放入 contentView。当前 SDK 15.5 构建使用降级材质。macOS 27 的交互 API 尚未编译验证，不能把设计目标写成已调用的能力。
macOS 14/15 使用 NSVisualEffectView，减少透明度时切实色，不冒称新系统玻璃。
Windows 采用系统支持的 Acrylic/backdrop 或克制的静态层次，fallback 到实色；不称 Apple Liquid Glass。
当前悬停增强边缘对比，空闲与按下无装饰动画等待。0.97 按压缩放是后续可选效果，尚未实现；启用时必须尊重减少动态效果，不能延迟捕获。
空闲不旋转、闪烁或循环动画。减少动态效果时不缩放，以瞬时高对比状态代替。
“录制中/暂停”状态由真实录制状态源推送，圆点不是默认红灯；录像尚在 Starting 时不能显示录制成功。
右键尽量使用原生系统菜单。macOS 27 对菜单图标的变化不影响文字动作表达。

## 7. 截图工作台
顶栏：截图 | 屏幕录制，活动屏上方居中。录屏入口已连接独立原生来源选择；不会把截图选框当成区域视频裁剪。
选区：边界用黑白双层/对比描边适应复杂背景，八个调整点可见；尺寸标签显示实际导出像素。
底栏目标顺序：提取文字 | 复制 | AirDrop（macOS）| 下载 ▾ | 分隔 | 取消 | 完成。
下载子菜单：保存、另存为、默认保存位置设置。
底栏初始高 40 pt/DIP，间距 4/8/12/16；小屏可折叠次要动作到可访问菜单。
优先位于选区外下方靠右，越界则上/侧方；全屏无法完全避开时停靠屏边，并提供隐藏与快捷键。
遮罩输入与动作栏焦点分离；Tab 顺序与视觉顺序一致，Enter 默认完成；OCR 编辑获得焦点后 Enter 保持编辑语义。
拖动有键盘替代：方向键移动选区，修饰键调大小，并在帮助中明确；Esc 始终回到可取消流程。
复制/保存失败留在当前选区，文字解释错误，重试不要求重新截图。
OCR 展示可编辑文本、识别状态与复制文本；不混淆“复制图片”和“复制文本”。
导出只从干净不可变底图裁切，绝不从 UI 合成截图导出。

## 8. 验收与资产清单
已交付：assets/symbol-black.svg、symbol-white.svg、app-dark.svg、app-light.svg；generated 内含深/浅 ICO/PNG、兼容 ICNS、悬浮球/菜单栏/托盘/Chrome 资源。icon-composer-layers 提供折角与圆点分层 SVG；它不是已编译的 .icon。
先平面符号 → 小尺寸 → 玻璃 → 最终构建接入，每步保留检查记录。
视觉检查：16/24/32/64/大尺寸、黑白/复杂背景、浅/深主题、减少透明度、减少动态效果、高对比。
交互检查：悬浮球拖动/停靠/恢复、鼠标与键盘、中文长标签、小屏避让、屏幕边缘、当前选区不被操作栏无故遮住。
性能检查：原生材质与实色 fallback 分别测，不能用 UI 数据库性能标签代替实际 GPU/CPU 数据。
实际接入：macOS bundle 使用 AppIcon.icns；Windows EXE 与 Inno Setup 引用品牌 ICO；Chrome 构建复制专用 16/32/48/128 PNG。Windows 安装器尚未构建。Chrome 弹出面板按系统深浅主题切换，深色头部使用白符号，打开面板时更新工具栏图标。原生 NSGlassEffectView/.icon、全平台辅助技术和透明背景合成对比度仍需实测，不能由联系表推断通过。

## 9. 本轮执行记录
2026-09-08 再次读取安装于 .agents/skills/ui-ux-pro-max/SKILL.md 的规则，并执行桌面截图、键盘反馈、权限和减少透明度的 UX 检索（work/ux-validation-2026-09-08.txt）。沿用已批准黑白桌面设计；不采纳网页骨架屏、营销 CTA 或网络字体建议。新增检查强调按钮完整可见、文本与图片复制语义分离、录制状态只由真实控制器驱动。

## 10. Desktop 0.2.1 update
Screenshot action width follows intrinsic native text size plus 16 pt horizontal insets (407 pt in the current Chinese layout). Recording controls expose a stable accessible panel title, pause/resume and stop/save identifiers, an explicit keyboard-focus path, and disabled stop during finalization. Native AX action tests passed; complete VoiceOver and physical keyboard workflows still need coverage. Window-scoped AX caches and latest-pointer coalescing preserve lightweight desktop hit testing. Chrome Web Store submission is paused by the user.

## Desktop region recording · 0.2.2
Keep the existing graphite/silver symbol and native material surfaces. Recording source picker adds a native text button “框选录制区域…” and a distinct “区域 · W × H px · 屏幕 ID” source. Region picking reuses the desktop overlay and keyboard resize/move behavior, with only Cancel / Use this region actions. Enter confirms a source, never starts recording or changes the clipboard. Escape closes the overlay. Pixel dimensions reflect the inward, even-pixel encoder crop. Cross-screen and stale display selections produce explicit recoverable errors. Screenshot exports keep the original image pixels; glass is UI-only. No new animation in the capture path. Focus and action guidance follows the installed UI UX Pro Max focused UX search for “keyboard focus modal recording selection”.
