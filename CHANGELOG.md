# Changelog

本文件记录 VideoHero Skill 的重要变更。

## [1.3.2] - 2026-11-08

### Added

- 新增版本匹配约定：Skill tag 名称对应 VideoHero App 版本；README 与安装参考补充版本查看、tag 切换、升级顺序和协议不匹配判断。
- 新增引擎与音色“补参”机制：生成前必须把 capabilities 里的全部引擎、以及所选引擎的全部音色展示给用户，由用户显式指定 `--engine` 与 `--voice`。
- 新增 `references/parameter-selection.md`：展示模板、委托选择、无交互宿主、歧义与失败重问规则。
- 协议版本 2：新增终态 `needs_review`（退出码 5）与工作流 `export-project`。
- 新增 `videohero presentation export --project <uuid>`：人工质检完成后复用既有讲解音频完成导出，不重新生成 TTS。
- `needs_review` 返回体携带 `reviewItems`（`page` / `reason` / `audioPath`）与 `nextAction`，供智能体把待审页面原样转告用户。

### Changed

- `1.3.2` tag 重建为本次最新 Skill 代码；App `1.3.1` 及更早版本需先升级到 `1.3.2` 或更高。
- README 更新到协议 2 现状：能力列表补充 `needs_review` 与 `presentation export`，推荐视频调用方式改为 doctor → render → wait → export，个人声音引擎范围与已启用引擎一致，安装步骤要求先检出同名 tag。
- `references/setup-and-testing.md` 增加版本匹配说明，并同步个人声音支持的引擎范围。
- 引擎列表只展示已启用引擎；未启用的 Ming-3.0-TTS 即使被 capabilities 声明也不展示、不可提交。
- `tts generate` 与 `presentation render` 提交前，引擎和音色必须来自用户显式选择；智能体不得依赖 CLI 兜底音色，也不得用标题、历史任务或记忆推断。
- 引擎与音色以外的参数继续使用默认值，并在提交摘要中声明；`presentation export` 复用项目既有引擎和音色，不重新询问。
- 智能体在收到 `needs_review` / 退出码 5 时**不得重试、不得重建项目**，应转告用户去 VideoHero 完成人工质检，再调用 `presentation export`。
- `capabilities.workflows` 现在会声明 `export-project`；`presentation.supportsExportExistingProject` 标识是否支持续跑导出。
- 协议版本不再兼容 1；CLI 与 App 必须同版本。

### Removed

- 撤回 `1.3.1` tag：其打包 CLI 仍是协议 1，与协议 2 文档不一致；不提供 1.3.1 的 Skill。

### Data

- 无 Skill 或 CLI 持久化格式变更；job 状态新增 `needs_review`，旧版本客户端无法解析。

## [0.3.0] - 2026-10-20

### Added

- 记录稳定个人音色 ID `videohero.personal-voice.v1`，以及 Qwen3 TTS、CosyVoice、MOSS-TTS Nano 的支持范围。
- 增加“我的声音”的发现、TTS/PPT 视频调用、授权恢复和验收说明。
- 增加个人音色需求分析、技术架构、数据库/持久化、风险、测试与开发计划文档。

### Changed

- 要求智能体只在 `voices list` 为所选引擎实际返回个人音色时使用该 ID，不能根据本地化标题猜测或静默替换引擎。
- 明确 Skill/CLI 不得替用户完成个人声音同意、登记、验证或读取参考音频；`authorization_required` 必须交还用户处理。

### Data

- 无数据库或 Skill 持久化格式变更；个人声音素材不进入 Skill、CLI job 或 Automation App Group。

## [0.2.0] - 2026-10-19

### Added

- 新增独立 CLI 权威路径 `bin/macos-universal/videohero` 及 SHA-256 清单约定。
- 新增 `scripts/verify.sh`，验证校验和、Developer ID、安全时间戳、Hardened Runtime、Team ID、Automation App Group、非沙盒 entitlement、Universal 架构和版本命令，并正确处理裸 CLI 的 `spctl` “not an app”说明。
- 新增 `scripts/install.sh`，安全地把已验证 CLI 原子复制到 `~/.local/bin/videohero`。
- 新增独立 CLI 随 Skill 分发的需求、架构、风险和开发验收文档。

### Changed

- CLI 从 TestFlight App 包内嵌入改为 Developer ID 签名、公证并随 Skill 独立分发。
- 已取得同 Team ID 的 Developer ID Application 签名身份，最终 Universal CLI 已通过 Apple 公证并发布；校验和、严格验签、Hardened Runtime、安全时间戳、Automation App Group、双架构、版本与隔离安装测试均通过。
- CLI 发现顺序改为“用户绝对路径 → `VIDEOHERO_CLI` → PATH → Skill 自带 CLI”。
- 明确 VideoHero App 仍负责全部生成和项目持久化，CLI 仍是薄客户端。
- 安装说明不再要求 App 设置页创建符号链接，也不再引用 App 内 CLI 或本地 Release 测试包。
- 安装产物改为独立副本，避免 App 更新、移动或 TestFlight 重签影响 CLI。

### Removed

- 移除 `/Applications/VideoHero.app/Contents/Helpers/videohero` 发现兜底。
- 移除扫描 DerivedData、`.build`、旧测试包和 App 私有 Helper 的可能性。

## [0.1.1] - 2026-10-19

### Added

- 支持从 VideoHero App 标准内嵌路径 `Contents/Helpers/videohero` 发现 CLI。
- 增加用户级 `~/.local/bin/videohero` 符号链接安装、更新、卸载和路径复制说明。
- PPTX/PDF 视频任务默认创建并持续保存可编辑的 VideoHero 项目。
- 增加项目持久化、项目目录、失败回滚和 UI 可见性的需求与架构文档。
- 增加项目列表、重启持久化、取消清理和 TTS-only 无项目的测试说明。
- 记录 VideoHero 演示文稿 job 的可选预计总耗时、已耗时、预计剩余时间和历史样本数。
- 增加 NDJSON 实时进度的解析和转述规则。
- 增加预计耗时与实时进度的需求、架构、持久化和测试文档。
- 增加项目 README、安装说明和推荐调用方式。
- 增加项目持久化版本的 Release 测试包、CLI 黑盒回归和签名/entitlement 验证记录。

### Changed

- 重写安装说明，明确 Skill 不包含二进制、CLI 随 App 嵌入、授权与命令入口安装是两个独立动作。
- 明确正式验收使用 TestFlight/正式渠道安装的 App，不要求额外本地 Release 测试包。
- CLI 解析增加 `/Applications`、`~/Applications` 标准 App 内路径兜底，并禁止扫描 DerivedData、`.build` 或调用私有 Helper。
- 明确 presentation 无需也不支持 `--save-project`；`capabilities.presentation.persistsProject` 是权威能力标志。
- 明确文字转 TTS 仍为临时音频 job，不创建 VideoHero 项目。
- 视频和语音示例改为先以 JSON 提交，再使用 `jobs wait --format ndjson` 持续等待。
- 明确 `--format json` 只返回单个最终 JSON，不用于实时进度。
- 明确没有历史样本时不得编造预计完成时间。
- 明确旧版已经完成但未写入项目库的历史视频 job 不会自动补录，需用新版重新运行。

## [0.1.0] - 2026-10-19

### Added

- 初始 VideoHero Skill。
- VideoHero CLI 能力发现、预检、文字转语音、PPTX/PDF 转视频和 job 管理指南。
