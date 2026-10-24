# GitHub 下载与发布

仓库首页的两个按钮使用固定附件名，指向 GitHub 最新发布版本：

| 用途 | Release 附件名 |
| --- | --- |
| macOS 主下载 | `Snapliq-macOS.dmg` |
| macOS ZIP | `Snapliq-macOS.zip` |
| Windows 主下载 | `Snapliq-Windows-Setup.exe` |
| Windows 免安装包 | `Snapliq-Windows-Portable.zip` |
| Windows 使用说明 | `README-Windows.zh-CN.txt` |
| 文件校验 | `SHA256SUMS.txt` |

固定地址格式为 `https://github.com/FIONN191/Snapliq/releases/latest/download/<附件名>`。每个历史版本保留自身的附件；用户也可以从发布历史选择具体版本。当前架构为 macOS Apple Silicon 和 Windows x64，新增架构时必须分别命名和标注，不能静默改变现有按钮的架构。

## 更新步骤

1. 选择已完成构建和相应测试的具体提交，记录 Actions 运行地址。下载该运行的两端产物，保留原始版本化文件。
2. 在独立发布目录中复制为上表的固定文件名，不修改二进制。核对版本、架构、签名状态、包完整性与原始 SHA-256，生成新的 `SHA256SUMS.txt`。
3. 以测试过的提交为目标创建版本标签和草稿 Release，上传全部附件。发布说明必须区分云端测试、实机验收和未完成项目，写明系统版本、架构与签名状态。
4. 对比草稿附件的名称、大小和 SHA-256，确认无遗漏后发布并设为 Latest。GitHub 的 `releases/latest` 不选择草稿或 prerelease；Latest 只代表此下载渠道的当前版本，不代表已完成正式签名或全部实机验收。开发版须在标题、说明和 README 中明确标注。
5. 不带账号或授权头重新下载六个固定地址，确认 HTTP 200、实际文件类型及哈希匹配。记录结果后更新 README 的版本与验收链接。

安装包放在 Release 附件中，不提交到源码 Git 历史。对已发布版本的更正应发布新版本并保留旧版，避免静默替换用户已经下载的文件。
