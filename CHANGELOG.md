# Changelog

本文件记录 VideoHero Skill 的重要变更。

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
