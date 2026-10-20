# VideoHero CLI“我的声音”支持：需求分析、技术架构和开发计划

日期：2026-10-20

状态：开发完成，待 TestFlight/正式安装包真实验收

## 1. 背景与问题

VideoHero 图形界面已经可以在用户完成 Pro 权限校验、声音使用同意、声音登记和参考音频验证后，使用“我的声音”生成 TTS 音频或 PPT 视频。当前自动化能力没有接通这条链路：

- `capabilities.presentation.supportsPersonalVoices` 被固定为 `false`；
- `voices list` 只返回引擎自带或 App 预设音色；
- 自动化预检和执行只在 `engine.availableVoices` 中查找音色；
- PPT 自动化显式拒绝个人音色。

因此，即使用户已经在 App 中完成声音克隆和授权，Codex、WorkBuddy、Qoder 等智能体仍无法发现或使用“我的声音”。这属于 VideoHero 自动化层的功能缺口，不是智能体发现能力不足。

## 2. 需求结论

### 2.1 功能目标

- CLI 在当前用户的个人声音授权有效时，通过 `voices list` 公布“我的声音”。
- 使用现有稳定 ID `videohero.personal-voice.v1`，不以本地化标题作为调用参数。
- 在支持个人声音的引擎下分别公布该音色：
  - `qwen3PresetVoice`
  - `cosyVoice`（仅平台实际公开该引擎时）
  - `mossTTSNano`
- `kokoroTTS` 不公布个人音色，因为该引擎没有个人声音克隆能力。
- CLI 的文字转语音和 PPTX/PDF 转视频均可选择“我的声音”。
- 真正执行任务前重新进行 Pro 权限和声音授权检查；授权撤销、过期或参考音频缺失时安全失败。
- 智能体只能看到稳定音色 ID、标题、语言和所属引擎，不得看到参考音频路径、登记文本、验证分数等隐私数据。

### 2.2 默认行为

- 未指定 `--voice` 时继续使用该引擎原有的默认预设音色，不自动改用“我的声音”。
- 未完成或已失效的个人声音授权时，`voices list` 不列出“我的声音”，`supportsPersonalVoices` 为 `false`。
- 已授权时，`supportsPersonalVoices` 为 `true`，且支持的引擎各自包含一个相同稳定 ID、不同 `engineID` 的个人音色条目。
- capability 快照只代表生成时的发现结果；任务执行仍以实时授权结果为准。

### 2.3 非目标

- 不允许 CLI 创建、录制、导入、替换或删除个人声音。
- 不允许智能体代替用户接受声音使用协议或购买 Pro。
- 不向 App Group 写入参考音频或其他个人声音素材。
- 不新增多个个人声音档案；本期继续使用 VideoHero 现有的单个“我的声音”。
- 不改变 TTS 临时任务和 PPT 项目持久化规则。

## 3. 用户与智能体体验

授权完成后，智能体按现有发现流程调用：

```bash
videohero capabilities --format json
videohero voices list --engine qwen3PresetVoice --format json
```

输出音色列表包含：

```json
{
  "id": "videohero.personal-voice.v1",
  "engineID": "qwen3PresetVoice",
  "title": "我的声音",
  "languageCode": "zh"
}
```

随后可用于 TTS 或 PPT 视频：

```bash
videohero tts generate \
  --text-file "/absolute/path/script.txt" \
  --output "/absolute/path/speech.wav" \
  --engine qwen3PresetVoice \
  --voice videohero.personal-voice.v1 \
  --format json
```

```bash
videohero presentation render \
  --pptx "/absolute/path/deck.pptx" \
  --pdf "/absolute/path/deck.pdf" \
  --output "/absolute/path/deck.mp4" \
  --engine qwen3PresetVoice \
  --voice videohero.personal-voice.v1 \
  --format json
```

若用户之后撤销授权，任务返回结构化 `authorization_required`，智能体应提示用户回到 VideoHero 的“我的声音”界面重新完成授权，不得换用其他声音静默重试。

## 4. 技术架构

### 4.1 能力发现

将 `VideoHeroCapabilityService.snapshot()` 改为异步构建：

1. 调用 `VideoHeroSyntheticMediaServices.shared.requireAuthorizedVoice()` 判断当前个人声音是否真正可用；
2. 只保留布尔结果，不把返回的参考音频 URL 或登记文本写入 capability；
3. 对每个公开引擎调用 `TTSVoiceCatalog.voices(for:includesPersonalVoice:)`；
4. 只有引擎声明 `.personalVoiceCloning` 时才加入个人音色；
5. 根据最终音色集合计算 `supportsPersonalVoices`。

App 启动、智能体控制开关变化、基础诊断以及任务预检均使用新的异步快照，避免继续写出固定的旧能力。

### 4.2 统一音色解析

新增自动化内部的音色解析逻辑，输入 `engineKind + voiceID + includesPersonalVoice`，输出 `TTSVoiceDescriptor`：

- 预设音色从现有引擎目录解析；
- 个人音色使用 `TTSVoiceDescriptor.personalVoice(for:)`；
- 不支持个人声音的引擎返回 `voice_not_found`；
- 个人音色授权失效时返回 `authorization_required`；
- 未指定音色时保持原默认预设音色逻辑。

TTS 和 PPT 工作流共用该规则，防止两个入口对个人音色的行为不一致。

### 4.3 执行边界和二次授权

能力发现成功不等于永久授权。生成引擎在真正读取参考声音前仍调用现有 `requireAuthorizedVoice()`：

- Qwen3 和 CosyVoice 通过 `AppPresetVoiceReferenceProvider.reference(for:)` 二次校验；
- MOSS-TTS Nano 通过现有个人参考音频解析路径二次校验；
- 授权错误转换为自动化可理解的 `authorization_required`，并给出回到 App 完成授权的恢复建议。

不复制授权实现，不绕过 SyntheticSpeechKit 的同意书和登记状态。

### 4.4 CLI 与协议兼容

现有协议已能通过 `ttsVoices` 表达相同音色 ID 在不同引擎中的条目，现有 `--voice` 参数也能传递该 ID，因此：

- 协议版本保持 v1；
- 不新增 CLI 参数；
- 不要求为本功能重新设计 job 文件；
- 独立 CLI 若只是透传现有字段，无需修改二进制；验证后再决定是否需要重新发布 CLI。

## 5. 数据库与持久化变化

### 5.1 数据库

**无数据库结构变更。**

原因：个人音色已经使用现有 SyntheticSpeechKit/VideoHero 授权和登记存储；项目也已有 `pptTTSVoiceDescriptorID` 与 `pptTTSEngineKind` 字段保存稳定音色 ID 和引擎。无需新增 SwiftData 实体或字段。

### 5.2 旧数据兼容与迁移

- 无数据库迁移。
- 旧项目中已经保存的 `videohero.personal-voice.v1` 继续有效。
- 旧 CLI/App 仍按协议 v1 解码新增的音色条目。
- 未授权用户得到的 capability 与当前行为兼容，不会凭空出现个人音色。

### 5.3 文件持久化

- 不新增个人声音文件。
- 不将参考音频复制到 Automation App Group、job 目录或 skill。
- TTS 仍为临时 job；PPT 视频仍按既有规则持续保存到 VideoHero 项目目录。

### 5.4 验证方法

- 检查 SwiftData schema 没有变化。
- 检查 capability JSON 不含参考音频路径、登记文本或授权上下文。
- 检查个人音色生成后项目只保存稳定音色 ID，不复制个人参考素材。

## 6. 界面变化

**无新增界面。**

继续使用现有“我的声音”界面完成购买、同意、登记、验证和撤销。智能体控制页的基础诊断会因为重新生成 capability 而反映个人声音是否可用，但本期不新增开关或声音管理入口。

## 7. 预计修改文件

### 7.1 VideoHero 现有文件

- `VideoHero/Automation/VideoHeroCapabilityService.swift`
  - 异步检查授权并向支持的引擎注入个人音色。
- `VideoHero/Automation/VideoHeroAutomationCoordinator.swift`
  - 异步刷新能力；TTS 使用统一的自动化音色目录；映射授权错误。
- `VideoHero/Automation/VideoHeroAutomationPreflightService.swift`
  - 验证个人音色和引擎组合。
- `VideoHero/Automation/VideoHeroPresentationAutomationWorkflow.swift`
  - 删除个人音色硬拒绝，使用统一音色解析并保留项目音色 ID。
- `VideoHero/View/Settings/VideoHeroAutomationSettingsView.swift`
  - 适配异步 capability 与诊断。
- `VideoHero/Services/VoiceClone/VideoHeroSyntheticMediaServices.swift`
  - “我的声音”授权可用性发生变化后，立即刷新自动化 capability，避免 CLI 继续读取旧音色目录。
- `VideoHeroTests/VideoHeroAutomationProtocolTests.swift`
  - 更新能力协议样例。
- `VideoHeroTests/VideoHeroAutomationPreflightServiceTests.swift`
  - 增加个人音色组合测试。
- `VideoHeroTests/VideoHeroPresentationAutomationWorkflowTests.swift`
  - 适配异步能力快照并验证个人音色声明。
- `README.md`、`CHANGELOG.md`
  - 记录 CLI 个人音色能力和授权边界。

根据实现复用情况，可能新增：

- `VideoHero/Automation/VideoHeroAutomationVoiceCatalog.swift`
  - 集中处理自动化音色发现、默认值与错误映射。
- 对应单元测试文件。

### 7.2 videohero-skill 现有文件

- `SKILL.md`
  - 明确个人音色发现、选择和授权失败处理。
- `references/cli-protocol.md`
  - 记录稳定个人音色 ID、支持引擎和安全边界。
- `README.md`、`CHANGELOG.md`
  - 补充用户安装后的使用说明和版本记录。
- `docs/20261020-cli-personal-voice.md`
  - 本需求分析、架构、计划和验证记录。

## 8. 风险与对策

### 8.1 capability 与实时授权不一致

授权可能在 capability 生成后撤销。执行时必须二次检查，并返回 `authorization_required`，不能仅信任快照。

### 8.2 隐私泄露

`requireAuthorizedVoice()` 返回参考音频 URL 和文本，但 capability 只使用“是否成功”的布尔结果；不序列化授权上下文。

### 8.3 引擎支持不一致

不得把个人声音机械加入所有引擎。以引擎 `.personalVoiceCloning` capability 为唯一代码依据，当前 Kokoro 必须排除。

### 8.4 默认行为意外变化

个人音色插入目录首位后，如果默认音色也从完整目录取首项，会意外改变默认声音。因此未指定 `--voice` 时必须继续从引擎原始预设目录选择第一项。

### 8.5 授权错误被泛化

底层授权错误若直接落入 `generation_failed`，智能体不知道如何恢复。自动化边界需统一映射为 `authorization_required` 并保留可操作提示。

## 9. 测试与验收计划

### 9.1 单元测试

- 未授权：不公布个人音色，`supportsPersonalVoices == false`。
- 已授权：Qwen3、CosyVoice、MOSS 各公布 `videohero.personal-voice.v1`。
- Kokoro 永远不公布个人音色。
- 预检接受“支持引擎 + 个人音色”组合。
- 预检拒绝“Kokoro + 个人音色”和未知音色。
- 未指定音色仍选择预设默认音色。
- capability JSON 不包含个人参考音频或登记文本。
- PPT 项目保存个人音色稳定 ID。

### 9.2 构建与回归

- 运行相关 XCTest。
- 构建 VideoHero App。
- 验证现有预设音色 TTS 和 PPT 工作流未回归。
- 验证独立 CLI 无需修改时仍可读取新增条目并原样提交 ID。
- 运行 skill `quick_validate.py` 和仓库 `scripts/verify.sh`。

### 9.3 真实验收

- 在 App 中已完成“我的声音”的账号上运行 `voices list`，看到三个支持引擎的个人音色。
- 使用 Qwen3 个人音色生成 WAV 成功。
- 使用个人音色生成 PPT 视频成功，项目在 VideoHero 界面中可见且音色设置正确。
- 撤销或破坏个人声音授权后，刷新 capabilities 不再列出；已提交任务安全返回 `authorization_required`。
- Qoder/WorkBuddy 能从 `voices list` 选择稳定 ID，不需要猜测标题或访问 App 私有数据。

## 10. 开发计划

### 阶段 A：文档与设计

- [x] 核对现有 UI 个人声音链路、引擎 capability 和自动化缺口。
- [x] 明确数据库、持久化、界面、兼容和隐私边界。
- [x] 写入本需求分析、技术架构和开发计划。

### 阶段 B：能力发现与执行

- [x] 异步生成 capability，并按实时授权公布个人音色。
- [x] 统一自动化音色目录与解析逻辑。
- [x] 接通 TTS 个人音色生成。
- [x] 接通 PPT 视频个人音色生成。
- [x] 将授权失效映射为结构化 `authorization_required`。
- [x] 适配设置页诊断和 capability 刷新调用。

### 阶段 C：测试与验证

- [x] 补充能力发现、预检和音色解析单元测试。
- [x] 运行相关 XCTest。
- [x] 完成 VideoHero App 构建验证。
- [x] 验证 CLI 的 voices、TTS 和 PPT 请求兼容性。

### 阶段 D：Skill 与发布文档

- [x] 更新 VideoHero README 和 CHANGELOG。
- [x] 更新 videohero skill、协议参考、README 和 CHANGELOG。
- [x] 运行 skill 结构与发布内容验证。
- [x] 补充本文验证记录并完成最终检查。

### 阶段 E：用户真实验收

- [ ] 用户 Archive 并通过 TestFlight/正式渠道安装包含本改动的 VideoHero。
- [ ] 使用 Qoder/WorkBuddy 查询三个支持引擎，确认能发现 `videohero.personal-voice.v1`，且 KokoroTTS 不返回该 ID。
- [ ] 分别完成一次个人音色 TTS 和 PPT 视频生成，并确认视频项目在 VideoHero 中可见。
- [ ] 撤销或破坏授权后确认任务返回 `authorization_required`，恢复授权后重新查询可发现。

## 11. 验证记录（2026-10-20）

- `xcodebuild test` 正常开发签名构建 VideoHero App；关闭并行测试后复用构建产物运行个人音色相关的 25 个 XCTest，0 失败，结果 `TEST EXECUTE SUCCEEDED`。
- 覆盖未授权/已授权 capability、支持引擎集合、Kokoro 排除、个人音色解析、授权错误映射、预检和 PPT 项目参数持久化回归。
- 独立 CLI `version --format json` 成功，返回 CLI `0.1.0`、协议 `1`；CLI 源码对 `voices list` 和 TTS/PPT 的 `--voice` 使用通用稳定 ID 透传，无需更改二进制或协议。
- skill-creator 的 `quick_validate.py` 校验通过。
- skill `scripts/verify.sh` 在可访问系统钥匙串/信任链的环境中通过：SHA-256、Developer ID、Hardened Runtime、双架构、Team ID 和 Automation App Group 均有效。沙盒内无法访问信任链时可能误报签名无效，不代表二进制被修改。
- 两个仓库的 `git diff --check` 均通过。
- 未运行真实个人声音推理，避免代替用户操作授权和耗费模型资源；真实生成留给用户打包后的阶段 E 验收。

## 12. 验收标准

- 已授权用户的 `voices list` 可以稳定发现“我的声音”。
- Qwen3、CosyVoice、MOSS 支持该 ID，Kokoro 不支持。
- TTS 与 PPT 视频都能使用个人音色完成生成。
- 未授权、授权撤销或参考音频缺失时不会泄露数据或绕过授权。
- 无数据库迁移、无新增 UI、无 CLI 参数变化。
- README、CHANGELOG、skill 和协议参考与实际实现一致。
