# VideoHero CLI 视频预计耗时与实时进度：需求分析、技术架构和开发计划

> 日期：2026-10-19  
> 状态：开发前方案  
> 涉及仓库：VideoHero、videohero-skill  
> 勾选规则：只有已经实现且完成相应验证的项目才标记为 `- [x]`

## 1. 背景与现状

VideoHero 图形界面在导出 PPT 视频前，会通过 `ExportHistoryManager` 根据 TTS 引擎、页数、待生成讲解词字数和历史导出记录预测耗时，并通过 Toast 告知用户。导出期间，界面还会持续显示当前阶段和完成百分比。

智能体自动化已经具备进度数据：App 会持续更新 job 的 `status.json`，包含 `stage`、`progress` 和 `message`；CLI 在 `jobs wait --format ndjson` 下也能轮询并输出变化。但是当前仍有以下缺口：

- CLI job 状态没有预计总耗时、已耗时和预计剩余时间。
- 自动化视频任务没有复用 GUI 的历史预测逻辑，也不会把成功任务写入导出历史。
- `presentation render --wait --format json` 只输出最终结果，不会显示中间进度。
- Skill 的视频示例使用 `--format json --wait`，导致 WorkBuddy、Qoder 或 Codex 按示例调用时看不到持续进度。
- CLI 的文本等待模式只打印最终结果。

## 2. 目标

### 2.1 功能目标

- [x] PPTX + PDF 视频 job 在 App 完成演示文稿解析后，尽早发布预计总耗时和预计剩余时间。
- [x] 预计耗时复用 GUI 的 `ExportHistoryManager`，避免 CLI 和 GUI 出现两套预测算法。
- [x] CLI 成功生成的视频任务写入同一份匿名性能历史，使后续预测能够学习 CLI 工作负载。
- [x] 智能体等待视频任务时，持续收到机器可解析的 NDJSON 进度。
- [x] 人工在终端使用文本格式等待时，持续看到百分比、阶段说明和预计剩余时间。
- [x] 最终结果仍明确区分“生成成功”和“产物已交付到目标路径”。
- [x] 更新 videohero-skill，使智能体默认采用“JSON 提交 + NDJSON 等待”的调用方式。

### 2.2 非目标

- 本轮不改变 GUI 导出页面、Toast 样式或现有 GUI 导出流程。
- 本轮不为没有任何历史记录的引擎虚构预计耗时；无有效样本时明确返回“暂不可预测”。
- 本轮不引入 XPC、后台 Helper 或新的常驻进程。
- 本轮不改变 TTS 音频 job 的耗时预测；先覆盖耗时明显更长的演示文稿转视频。
- 本轮不把 `--format json` 改成多条输出；JSON 模式继续保证 stdout 只有一个最终 JSON 文档。

## 3. 用户与智能体体验

### 3.1 推荐调用流程

智能体先以 JSON 模式快速提交任务并取得 job id：

```bash
videohero presentation render \
  --pptx "/absolute/path/deck.pptx" \
  --pdf "/absolute/path/deck.pdf" \
  --output "/absolute/path/deck.mp4" \
  --engine <engine-id> \
  --voice <voice-id> \
  --format json
```

随后用 NDJSON 等待：

```bash
videohero jobs wait <job-id> --format ndjson
```

预计输出会先包含普通阶段进度；当 App 完成 PPTX 解析并取得页数、讲解词和历史样本后，后续状态会带上可选的 `estimate`：

```json
{"state":"running","stage":"generating-narration","progress":0.31,"message":"正在生成第 2/8 页讲解","estimate":{"estimatedTotalSeconds":420,"elapsedSeconds":58,"estimatedRemainingSeconds":362,"basedOnRecordCount":3,"updatedAt":"2026-10-19T07:20:00Z"}}
```

没有有效历史样本时，`estimate` 为空；job 仍正常执行，智能体不得把“没有预测”当成失败。

### 3.2 文本模式

`videohero jobs wait <job-id>` 应在状态变化时逐行显示，例如：

```text
running 31% 正在生成第 2/8 页讲解，预计剩余约 6 分钟
running 68% 正在渲染第 3/8 页视频，预计剩余约 2 分钟
finalizing 99% 正在登记视频产物
succeeded 100% 演示文稿视频生成完成
delivered /absolute/path/deck.mp4
```

### 3.3 输出格式约束

- `--format ndjson`：每次状态变化输出一行独立 JSON，并立即写入 stdout。
- `--format text`：每次状态变化输出一行用户可读进度。
- `--format json`：保持单 JSON 文档语义，只输出最终结果；需要实时进度的智能体必须改用 NDJSON。
- stdout 只承载协议结果；诊断信息继续使用 stderr。
- 等待进程断开不取消 job；智能体可再次运行 `jobs wait` 或 `jobs status`。

## 4. 协议设计

### 4.1 新增可选计时对象

在共享协议中新增：

```swift
struct VideoHeroAutomationTimingEstimate: Codable, Equatable, Sendable {
    var estimatedTotalSeconds: Double
    var elapsedSeconds: Double
    var estimatedRemainingSeconds: Double
    var basedOnRecordCount: Int
    var updatedAt: Date
}
```

并在以下对象中增加可选字段：

- `VideoHeroAutomationStatus.estimate`
- `VideoHeroAutomationEvent.estimate`

所有秒数必须为有限且非负的数；`estimatedRemainingSeconds` 不得为负。任务成功时剩余时间归零，实际耗时可以超过最初预测值。

### 4.2 兼容策略

- 本次仅增加可选 JSON 字段，协议版本继续为 v1。
- 新 CLI 读取旧 App 状态时，缺少 `estimate` 应解码为 `nil`。
- 旧 CLI 读取新 App 状态时会忽略未知字段。
- 不改变 job 状态机、退出码和交付回执结构。
- 不以 `progress == 1` 代替成功判断；仍要求终态为 `succeeded` 且 `delivery.state == delivered`。

## 5. App 技术架构

### 5.1 预测计算时机

自动化工作流完成以下步骤后计算预测：

1. 解析 PPTX 正文和备注。
2. 校验 PDF 页数并生成页面图。
3. 按 `notes`、`body` 或 `notes-or-body` 得到每页最终讲解词。
4. 使用 `PPTNarrationLengthPolicy.equivalentLength` 计算总等效朗读长度。
5. 调用 `ExportHistoryManager.prediction`，传入引擎、页数、总字数及待生成 TTS 字数。

选择这个时机是因为提交 CLI job 时只有文件路径，尚未得到可靠页数和最终讲解词；CLI 不应自行解析 PPTX 或复制 App 的业务规则。

### 5.2 剩余时间更新

- 初次预测时记录预计总耗时、已耗时和样本数。
- 每次 progress 更新时，根据实际已耗时刷新 `elapsedSeconds` 和 `estimatedRemainingSeconds`。
- 预计总耗时保持本次 job 的初始预测值，不随进度百分比机械缩放，避免阶段权重造成大幅跳动。
- 成功终态写入实际已耗时并把剩余时间设为 0。
- 失败或取消时保留最后一次估计，便于诊断，但不把失败任务加入历史样本。

### 5.3 历史学习

成功且产物验证通过后，自动化视频任务写入 `ExportHistoryManager`：

- 引擎
- 页数
- 总等效朗读长度
- 总耗时
- 实际生成的 TTS 页数和字数
- TTS 阶段耗时
- 非 TTS 阶段耗时

不保存 PPT/PDF 路径、文件名、讲解词内容、音色或用户身份信息。

## 6. CLI 技术架构

### 6.1 等待循环

保留现有 250 ms 状态轮询模型，并调整输出：

- 状态 `updatedAt` 变化且未终态时：NDJSON 和文本模式立即输出。
- JSON 模式不输出中间状态。
- 终态后输出包含交付回执的最终结果。
- JSON/NDJSON 写入改为直接写 `FileHandle.standardOutput`，确保管道消费者及时收到每一行。

### 6.2 格式化

- NDJSON 原样输出结构化 `estimate`。
- 文本模式把预计剩余秒数格式化为秒、分钟或小时/分钟。
- 不在 CLI 中重新计算预测模型；CLI 只展示 App 发布的权威状态。

## 7. 数据库与持久化变化

### 7.1 SwiftData

**无 SwiftData 数据库变更。**

原因：job 状态属于 App Group 文件协议，导出历史已经使用 UserDefaults，不属于项目、场景或模型库的 SwiftData schema。因此：

- 不新增 SwiftData entity 或字段。
- 不需要数据库迁移脚本。
- 不影响旧项目、场景、字幕或模型数据。

### 7.2 App Group job 文件

`status.json` 和 `events.ndjson` 增加可选 `estimate` 对象。旧文件没有该字段时仍可读取，无需批量迁移。

### 7.3 导出历史

沿用现有 `videohero.export.history` UserDefaults key 和 `ExportRecord` Codable 结构。CLI 成功任务只会追加兼容的记录；仍遵守最多保留 10 条的现有策略。旧记录无需转换。

### 7.4 验证方法

- 使用缺少 `estimate` 的旧 status fixture 验证新代码可解码。
- 使用包含 `estimate` 的新 status 验证 Codable round-trip。
- 使用旧版 `ExportRecord` JSON 验证可继续解码。
- 验证失败和取消任务不写入导出历史。

## 8. 界面变化

本轮 **无 GUI 界面变化**。

- 现有导出 Toast 和进度条保持不变。
- CLI 预测复用同一计算服务，但不会额外弹出 Toast。
- 智能体通过 CLI stdout 获取预测和进度，不依赖读取或操作 SwiftUI 界面。

## 9. 预计修改文件

### 9.1 VideoHero 仓库

- `SharedAutomation/VideoHeroAutomationProtocol.swift`
  - 新增计时估计模型及 status/event 可选字段。
- `SharedAutomation/VideoHeroAutomationJobStore.swift`
  - 校验 estimate 数值，并保持旧状态兼容。
- `VideoHero/Automation/VideoHeroPresentationAutomationWorkflow.swift`
  - 计算预测、统计实际耗时并返回性能指标。
- `VideoHero/Automation/VideoHeroAutomationCoordinator.swift`
  - 把预测和动态剩余时间写入 job 状态，成功后保存历史。
- `VideoHeroCLI/main.swift`
  - 文本模式持续输出，NDJSON 立即刷新，并格式化预计剩余时间。
- `VideoHeroTests/VideoHeroAutomationProtocolTests.swift`
  - 增加新旧 status 兼容和 estimate round-trip 测试。
- `VideoHeroTests/VideoHeroAutomationJobStoreTests.swift`
  - 增加 estimate 合法性、进度单调和持久化测试。
- `VideoHeroTests/VideoHeroPresentationAutomationWorkflowTests.swift`
  - 增加等效字数与预测输入构造测试。
- `scripts/test_videohero_cli_blackbox.sh`
  - 增加多条 NDJSON、文本进度和 estimate 输出测试。
- `scripts/prepare_videohero_agent_testkit.sh`
  - 改为从独立 `videohero-skill` Git 仓库打包 Skill，避免项目内旧副本漂移。
- `docs/agent-automation/03-protocol-v1.md`
  - 同步协议字段和输出示例。
- `docs/agent-automation/04-development-plan.md`
  - 同步开发与验证勾选状态。

### 9.2 videohero-skill 仓库

- `SKILL.md`
  - 明确 JSON 提交、NDJSON 等待和预计时间的处理方式。
- `references/cli-protocol.md`
  - 更新 PPT 视频示例、estimate schema 和实时进度说明。
- `references/setup-and-testing.md`
  - 更新烟雾测试和进度验证方式。
- `README.md`
  - 开发完成后补充面向用户的实时进度与预计耗时能力。
- `CHANGELOG.md`
  - 开发完成后记录本次功能、兼容性和使用方式。

### 9.3 预计新增文件

- 本设计文档：`docs/20261019-cli-video-estimate-and-live-progress.md`

暂不预计新增生产 Swift 文件；若实现过程中拆分独立计时模型能显著降低 Coordinator 复杂度，需先在本文件记录原因再新增。

## 10. 风险与处理

### 10.1 首次使用没有预测

风险：某个引擎没有成功导出历史时，无法可靠预测。

处理：`estimate` 保持为空，进度照常输出；Skill 明确要求智能体报告“暂无历史预测”，不得编造时间。

### 10.2 预测不准确

风险：模型冷启动、文本长度、字幕渲染和机器负载会造成偏差。

处理：标明这是 estimate；提供样本数；持续输出实际进度和剩余时间；不承诺完成时刻。

### 10.3 stdout 缓冲

风险：CLI 被智能体以管道方式运行时，普通 `print` 可能延迟交付。

处理：结构化输出使用 `FileHandle.standardOutput.write`，每条记录以换行结尾。

### 10.4 快速状态被轮询漏过

风险：250 ms 内连续更新可能只显示最新一次状态。

处理：本轮保证“持续可观察”，不承诺每个底层回调都逐条输出；关键阶段和百分比保持在最新 status。后续若需要完整事件重放，再把 `jobs wait` 切换为按 sequence 消费 `events.ndjson`。

### 10.5 跨版本兼容

风险：新旧 App/CLI 混用。

处理：只增加可选字段并保留 protocol v1；Skill 始终先检查 `version` 和 `capabilities`。

## 11. 测试计划

### 11.1 单元测试

- [x] estimate Codable round-trip。
- [x] 新代码读取不含 estimate 的旧 status/event。
- [x] 负数、NaN、Infinity estimate 被拒绝。
- [ ] 剩余时间不小于 0，成功时归零。
- [x] 预测使用指定引擎、页数和等效朗读长度。
- [ ] 失败或取消任务不写入历史。
- [ ] CLI 成功任务写入的 `ExportRecord` 可被现有预测读取。

### 11.2 CLI 黑盒测试

- [x] `jobs wait --format ndjson` 输出多条可独立解析的 JSON。
- [x] NDJSON 中间状态包含 stage、progress、message 和可选 estimate。
- [x] 文本模式输出多条进度，并展示预计剩余时间。
- [x] `--format json --wait` 仍只输出一个最终 JSON 文档。
- [x] stdout/stderr 保持分离。
- [x] 成功、失败、取消和交付失败退出码无回归。

### 11.3 App 与工作流测试

- [x] VideoHero Debug 构建通过。
- [x] VideoHeroCLI Debug 构建通过。
- [ ] 有历史样本时，真实 PPTX/PDF job 在 TTS 开始前发布 estimate。
- [ ] 无历史样本时，job 正常执行且 estimate 为空。
- [ ] progress 全程不回退。
- [ ] 成功任务写入历史，下一次预测包含新增样本。

### 11.4 Skill 测试

- [x] `quick_validate.py` 通过。
- [x] Skill 中所有内部引用存在。
- [x] 示例不再使用 JSON 长时间等待来假装实时进度。
- [ ] Codex、WorkBuddy 或 Qoder 能解析 NDJSON 并向用户转述阶段、百分比和预计剩余时间。

## 12. 验收标准

- [x] 智能体提交 PPT 视频任务后能取得 job id。
- [ ] 有历史数据时，job 状态在解析完成后出现预计总耗时和预计剩余时间。
- [ ] 无历史数据时返回明确的“暂无预测”语义，不影响生成。
- [x] 智能体等待期间至少在关键阶段持续收到进度，而不是只在完成时收到一次结果。
- [x] 进度百分比单调不回退，预计剩余时间不为负数。
- [x] 最终结果包含真实交付路径，且仅在 `succeeded + delivered + exit 0` 时视为成功。
- [ ] GUI 导出行为无回归。
- [x] 无 SwiftData schema 变化，无旧项目迁移。
- [x] VideoHero 与 CLI 构建通过，相关自动化测试和 Skill 校验通过。
- [x] README 和 CHANGELOG 已在开发完成后更新。

## 13. 开发计划

### 阶段 1：协议和预测数据

- [x] 新增可选 estimate 协议模型。
- [x] 增加 JobStore 合法性校验和兼容测试。
- [x] 在演示文稿自动化工作流中构造预测输入。
- [x] 在 Coordinator 中发布、刷新并完成 estimate。
- [x] 成功后保存匿名导出性能记录。

### 阶段 2：CLI 实时输出

- [x] NDJSON 输出改为立即写入 stdout。
- [x] 文本等待模式持续输出非终态进度。
- [x] 文本模式增加预计剩余时间。
- [x] 扩展 CLI 黑盒测试。

### 阶段 3：Skill 与协议文档

- [x] 修改 videohero-skill 的 `SKILL.md`。
- [x] 更新 CLI 协议参考和安装测试参考。
- [x] 更新 VideoHero 仓库的协议和开发计划文档。
- [x] 运行 Skill quick validation。

### 阶段 4：构建、联调和交付文档

- [x] 运行 Swift 单元测试。
- [x] 运行 CLI 黑盒测试。
- [x] 构建 VideoHero App 和 VideoHeroCLI。
- [ ] 用可用 fixture 或真实 PPTX/PDF 验证预计时间和持续进度。
- [x] 更新 videohero-skill `README.md`。
- [x] 更新 videohero-skill `CHANGELOG.md`。
- [x] 复核两个仓库的 `git diff --check` 和工作区变更。
