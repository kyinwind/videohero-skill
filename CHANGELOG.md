# Changelog

本文件记录 VideoHero Skill 的重要变更。

## [0.1.1] - 2026-10-19

### Added

- PPTX/PDF 视频任务默认创建并持续保存可编辑的 VideoHero 项目。
- 增加项目持久化、项目目录、失败回滚和 UI 可见性的需求与架构文档。
- 增加项目列表、重启持久化、取消清理和 TTS-only 无项目的测试说明。
- 记录 VideoHero 演示文稿 job 的可选预计总耗时、已耗时、预计剩余时间和历史样本数。
- 增加 NDJSON 实时进度的解析和转述规则。
- 增加预计耗时与实时进度的需求、架构、持久化和测试文档。
- 增加项目 README、安装说明和推荐调用方式。
- 增加项目持久化版本的 Release 测试包、CLI 黑盒回归和签名/entitlement 验证记录。

### Changed

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
