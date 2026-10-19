# VideoHero CLI 项目持久化：需求分析、技术架构和开发计划

> 日期：2026-10-19  
> 状态：功能已实现，等待真实 PPTX/PDF 与 WorkBuddy/Qoder 验收  
> 涉及仓库：VideoHero、videohero-skill  
> 勾选规则：只有已经实现并完成相应验证的项目才标记为 `- [x]`

## 1. 背景与问题

当前 `videohero presentation render` 能生成并交付视频，但其内部使用临时 `VHProject`/`VHScene` 对象：PPTX/PDF 的解析结果、页面图和讲解音频主要写入 automation job 工作目录，任务结束后还会删除以 job id 命名的项目目录。该项目没有插入 VideoHero 的 SwiftData，因此不会出现在项目列表，也不能在界面中继续编辑。

这与用户预期不一致。CLI 是 VideoHero 的另一种操作入口，不应形成一套“只生成产物、不创建项目”的平行流程。对于 PPTX/PDF 转视频，CLI 应与界面导入遵循同一项目生命周期：先创建项目，再导入和生成；处理中持续保存项目数据和缓存；成功后完成项目状态，而不是成功后才补写一条数据库记录。

## 2. 需求结论

### 2.1 功能目标

- [x] `presentation render` 通过预检后、正式解析前，在 SwiftData 中创建 PPT 项目并保存，使项目在 CLI 任务执行期间即可出现在 VideoHero 项目列表。
- [x] CLI 项目默认持久化，不新增 `--save-project`、`--no-save-project` 或等价参数。
- [x] 项目标题默认使用 PPTX 文件名，例如“16、外星世界-我与外星人思维对话实录（宋世鹏）-欧塔星-图文版”。
- [x] PPTX、PDF、页面图、首页缩略图、逐页 TTS、字幕对齐缓存、逐页预览视频和项目内最终视频均复用界面项目目录约定。
- [x] 项目目录位于 VideoHero 沙盒的 `Documents/projects/<project-folder>/`；当前安装对应 `/Users/yangxuehui/Library/Containers/com.michaeldev.VideoHero/Data/Documents/projects`。
- [x] CLI 生成期间按关键阶段保存 SwiftData；用户打开项目时看到的页面、讲解词、音色、字幕、比例、音频与当前任务进度一致。
- [x] CLI 的指定输出路径继续作为交付目标；同时保留项目目录内的最终视频副本，保证项目在界面中可继续访问已导出视频。
- [x] 任务失败或取消时，沿用界面导入失败的清理语义：删除本次新建的 SwiftData 项目和对应项目目录，不留下不可用半成品。
- [x] `capabilities.presentation.persistsProject` 改为 `true`，Skill 告知智能体视频任务会默认创建可编辑项目。

### 2.2 非目标

- 本轮不改变文字转语音 job：单次 TTS 仍是独立音频任务，不创建空的视频项目。
- 本轮不新增后台 Helper 或 XPC。
- 本轮不支持 CLI 修改一个既有项目，也不增加 `--project-id`。
- 本轮不改变用户指定输出文件的覆盖确认、交付回执或 job 状态机。
- 本轮不为项目列表新增“CLI 创建”徽标、筛选或独立页面。

## 3. 与界面操作一致的生命周期

CLI 演示文稿任务按以下顺序执行：

1. 读取并校验 job 请求、PPTX/PDF、引擎、音色和授权。
2. 使用 job id 作为项目 id，创建 `VHProject`，立即插入并保存到 App 的 `ModelContext`。
3. 创建 `Documents/projects/<job-id>/`，把输入 PPTX/PDF 复制为项目内 `source.pptx`、`source.pdf`。
4. 解析 PPTX，并把 PDF 页面图直接写入项目的 `ppt_slides/`。
5. 创建 `VHScene`，写入页面图、正文、备注和最终讲解词，插入 SwiftData 并保存。
6. 把逐页 TTS 直接写入项目的 `ppt_tts/<scene-id>.wav`；每页完成后更新 `generatedAudioPath`、时长、签名并保存。
7. 复用 `PPTScenePreviewService`，把逐页预览写入项目的 `ppt_preview/`；每页完成后保存场景缓存字段。
8. 把合并后的最终视频写入项目的 `export/`，校验后更新 `exportedVideoPath`、`duration`、`subtitle`、`stage` 和 `updatedAt` 并保存。
9. 将项目内最终视频复制到 automation job artifact，沿用现有 CLI 交付流程写入用户指定输出路径。
10. 成功时保留项目及缓存；失败或取消时删除本次项目和项目目录。

项目创建不是成功后的补偿动作。项目列表通过 SwiftData `@Query` 自动感知插入和更新，不需要 CLI 操作 SwiftUI，也不需要手工刷新列表。

## 4. 技术架构

### 4.1 ModelContext 注入

`VideoHeroAutomationCoordinator` 当前没有 SwiftData 依赖。改造后由 `VideoHeroApp` 在启动 Coordinator 和处理 automation URL 时注入 `sharedModelContainer.mainContext`。Coordinator 与 presentation workflow 均为 `@MainActor`，项目模型的创建、关系修改和 `save()` 保持在主 actor，避免跨线程使用 SwiftData 对象。

若 Coordinator 尚未取得 `ModelContext`，presentation job 不应退化为临时项目；应以可恢复错误结束并提示重新启动/打开 VideoHero。TTS job 不受影响。

### 4.2 项目标识和幂等性

使用 automation `jobID` 作为 `VHProject.id` 和 `projectFolderName`：

- 同一 job 在项目库和 App Group job store 中可直接关联。
- 扫描到重复 job 时可以先查询项目 id，防止重复插入。
- 项目目录名稳定且符合现有 UUID 目录约定。

正常协议不允许同一终态 job 再次执行。若启动时发现同 id 项目已经存在，工作流应拒绝重复创建并返回明确错误，而不是覆盖用户可能已编辑的数据。

### 4.3 项目文件布局

继续通过 `ProjectFileManager` 解析根目录，不在代码中硬编码用户绝对路径。预期目录包括：

```text
Documents/projects/<job-id>/
├── source.pptx
├── source.pdf
├── thumbnail.jpg
├── ppt_slides/
├── ppt_tts/
├── ppt_preview/
├── ppt_subtitle_alignment/
└── export/
    └── presentation.mp4
```

automation job 的 `artifacts/presentation.mp4` 是协议交付副本，不是项目的唯一视频。`VHProject.exportedVideoPath` 指向项目 `export/` 内的文件，使用户完成 CLI 调用后仍可从 VideoHero 界面访问项目视频。

### 4.4 复用与职责边界

- 继续复用 `PPTDocumentParser`、`PPTSlideThumbnailService`、`PPTScenePreviewService`、`PPTVideoExportService` 和 `ProjectFileManager`。
- 不让 Skill 或 CLI 直接写 SwiftData、项目目录或缓存；所有持久化由 VideoHero App 进程完成。
- presentation workflow 负责项目创建、逐阶段更新和项目内文件路径。
- Coordinator 负责注入 ModelContext、终态、job artifact、失败/取消清理和导出历史。
- 若实现中能通过小型项目会话对象减少重复清理逻辑，可新增 production Swift 文件；不得复制一套 UI 导入服务。

## 5. 数据库与持久化变化

### 5.1 SwiftData

**有业务数据写入变化，但无 SwiftData schema 变更。**

本功能复用现有 `VHProject` 和 `VHScene` 实体、字段及关系，不新增字段、实体、索引或关系，因此：

- 不需要 schema migration 或旧数据批量迁移。
- 旧项目读取和编辑行为不变。
- 新增行为是 presentation CLI job 会插入一条 `VHProject` 和多条 `VHScene`，并在生成期间更新现有字段。

需要写入或更新的现有项目字段至少包括：标题、副标题、来源类型、项目目录名、项目内源文件路径、比例、字幕开关、TTS 引擎、音色、页数、缩略图、最终视频路径、时长、阶段和更新时间。场景写入页面图、正文、备注、讲解词、生成音频、时长、音频签名和预览缓存字段。

### 5.2 旧数据兼容与迁移

无需迁移。验证重点是：

- 使用现有持久化 ModelContainer 打开旧数据库正常。
- 创建 CLI 项目后旧项目数量和内容不被修改。
- 重启 App 后 CLI 项目及其场景仍存在，所有项目内路径可访问。
- 删除 CLI 项目时继续通过现有删除流程移除数据库记录和项目目录。

### 5.3 文件持久化

CLI 视频项目的可编辑资源从 job `work/presentation` 迁移到 `ProjectFileManager` 管理的项目目录。App Group job store 继续保存请求、状态、事件和交付 artifact；其作用是自动化协议与交付，不替代项目资产库。

### 5.4 失败与取消

为保持与界面导入一致：

- 项目创建前失败：不产生项目或项目目录。
- 项目创建后失败/取消：Coordinator 删除本次项目、级联场景，并删除项目目录。
- 清理失败：保留 job 的原始失败信息，同时记录清理诊断日志；不得把清理失败伪装成生成成功。
- 成功终态后不再清理项目目录。

## 6. 界面变化

**项目列表会发生数据层面的可见变化，但不新增或重排 UI 控件。**

- CLI presentation job 创建后，项目列表自动出现对应标题的 PPT 项目。
- 导入页面和讲解词写入后，项目入口由“继续设置”切换为“继续编辑”。
- 成功导出后，项目阶段显示为完成，可打开查看和继续编辑。
- 失败或取消后项目从列表移除，与界面导入失败时的处理一致。
- 不弹出额外窗口，不抢占用户当前编辑页面，不因 CLI job 自动导航到新项目。

## 7. 协议与 Skill 变化

- CLI 命令和参数不变；默认行为即为创建并保存项目。
- `VideoHeroCapabilityService` 把 `presentation.persistsProject` 从 `false` 改为 `true`。
- 协议 v1 保持不变，因为字段已经存在，仅能力值变化。
- Skill 继续禁止智能体直接写数据库和项目目录，并说明 presentation job 成功后可在 VideoHero 项目列表继续编辑。
- Skill 不得建议或探测不存在的 `--save-project` 参数。

## 8. 预计修改文件

### 8.1 VideoHero 仓库现有文件

- `VideoHero/VideoHeroApp.swift`
  - 向自动化 Coordinator 注入 `ModelContext`。
- `VideoHero/Automation/VideoHeroAutomationCoordinator.swift`
  - 管理持久化项目会话、终态保存、artifact 副本和失败/取消清理。
- `VideoHero/Automation/VideoHeroPresentationAutomationWorkflow.swift`
  - 从临时项目改为持久化项目；把全部可编辑缓存写入项目目录并分阶段保存。
- `VideoHero/Automation/VideoHeroCapabilityService.swift`
  - 发布 `persistsProject: true`。
- `VideoHeroTests/VideoHeroPresentationAutomationWorkflowTests.swift`
  - 增加项目构造、文件路径和持久化相关单元测试。
- `VideoHeroTests/VideoHeroAutomationProtocolTests.swift`
  - 更新 capability 预期。
- `docs/agent-automation/01-requirements.md`
- `docs/agent-automation/02-architecture.md`
- `docs/agent-automation/03-protocol-v1.md`
- `docs/agent-automation/04-development-plan.md`
- `docs/agent-automation/05-agent-testing-guide.md`
- `docs/20261018智能体操作VideoHero技术方案和开发计划.md`
  - 移除“临时项目、不写 SwiftData”的旧结论，记录默认持久化行为和验证步骤。

### 8.2 videohero-skill 仓库现有文件

- `SKILL.md`
  - 说明 presentation job 默认创建可编辑项目，同时维持“智能体不得直接写项目目录/数据库”的边界。
- `references/cli-protocol.md`
  - 说明持久化项目语义和能力发现字段。
- `references/setup-and-testing.md`
  - 增加项目列表、重启持久化和项目目录 smoke test。
- `README.md`
  - 开发完成后补充默认项目持久化能力。
- `CHANGELOG.md`
  - 开发完成后记录本次行为变化。

### 8.3 可能新增文件

若持久化生命周期需要从 workflow/Coordinator 中抽离，预计新增：

- `VideoHero/Automation/VideoHeroAutomationProjectSession.swift`
  - 封装项目创建、分阶段保存、成功提交和失败回滚。

只有实现中确认能降低生命周期错误风险时才新增；当前文档不把该文件描述为已实现。

## 9. 风险与对策

### 9.1 SwiftData 与异步任务

风险：把 `VHProject`/`VHScene` 跨 actor 使用会触发并发问题。  
对策：Coordinator、workflow 和所有模型修改保持 `@MainActor`；耗时服务内部异步执行，但模型回写回到主 actor。

### 9.2 文件只有部分生成

风险：进程退出时数据库和文件目录处于中间状态。  
对策：每个阶段保存可恢复的现有字段；当前 restart recovery 会把中断 job 标记失败，随后清理对应自动化项目。未来若要断点续作再单独设计，不在本轮假装支持。

### 9.3 artifact 与项目视频重复占用空间

风险：项目副本和 job artifact 占用两份空间。  
对策：首版优先保证项目持久性和协议交付隔离；禁止让 delivery 移动或删除项目唯一副本。后续可评估安全的 clone/link，但不在本轮引入文件系统兼容风险。

### 9.4 用户在生成期间编辑项目

风险：用户打开正在生成的项目并修改讲解词或配置，会与自动化回写冲突。  
对策：本轮不自动打开项目；项目副标题明确显示正在由智能体生成。自动化以自身请求参数为准。若实际测试发现并发编辑容易造成损坏，应增加只读/忙碌保护作为后续需求，而不是隐藏项目直到成功。

### 9.5 同 job 重复执行

风险：重复插入相同 UUID 或覆盖已完成项目。  
对策：创建前查询同 id 项目和目录；发现冲突时失败，不覆盖或删除已有项目。

## 10. 测试与验收计划

### 10.1 自动化测试

- [ ] 内存 ModelContainer 中启动 presentation 项目会立即插入一个 `VHProject`。
- [ ] 创建的项目 id、目录名、标题、source type、引擎、音色、字幕和比例正确。
- [ ] 场景插入后重新 fetch 可读取，关系和排序正确。
- [ ] 项目所有可编辑资源路径均位于 `ProjectFileManager.projectDirectory` 下。
- [ ] 成功后 `exportedVideoPath` 指向项目 `export/`，项目阶段为 completed。
- [ ] job artifact 与项目视频都存在且哈希一致。
- [ ] 失败/取消删除数据库项目及项目目录。
- [ ] 同 id 项目冲突不会覆盖既有数据。
- [ ] TTS-only job 不创建 `VHProject`。
- [x] capability 返回 `persistsProject: true`。

### 10.2 构建与回归

- [x] VideoHero Debug 构建通过。
- [x] VideoHeroCLI Debug 构建通过。
- [x] VideoHero 和 VideoHeroCLI Release 构建及代码签名校验通过；已生成包含 App、CLI、Skill、Skill ZIP 和测试指南的本机测试包。
- [x] CLI 黑盒回归通过，覆盖 JSON/NDJSON、实时进度、预计剩余时间、退出码与交付重试。
- [ ] automation、PPT workflow 和协议定向测试整体通过。新增 7 个定向用例均已执行通过，但本机 Xcode 在测试完成后仍返回既有 LaunchServices runner 启动错误，因此不把整条 test action 标记为通过。
- [ ] 既有 GUI PPT 导入、编辑和导出路径不受影响。
- [x] Skill `quick_validate.py` 通过。

### 10.3 真实验收

- [ ] 使用 CLI 导出“16、外星世界-我与外星人思维对话实录（宋世鹏）-欧塔星-图文版”。
- [ ] 任务开始后，在 VideoHero 项目列表看到该项目，无需等生成成功。
- [ ] 生成期间打开项目，页面图、讲解词和已完成音频逐步可见且路径位于 `Documents/projects`。
- [ ] 成功后项目显示完成，可在界面继续编辑并重新导出。
- [ ] 退出并重启 VideoHero 后项目仍存在，页面图、音频、预览和最终视频均可访问。
- [ ] CLI 指定的目标 MP4 正常交付，job 状态、实时进度和预计耗时不回退。
- [ ] 主动取消一个测试 job 后，项目列表和项目目录均无残留。

## 11. 开发计划

### 阶段 A：文档和设计

- [x] 确认 CLI presentation 默认持久化，不增加开关参数。
- [x] 明确项目应在任务开始阶段创建，而不是成功后补写数据库。
- [x] 明确复用 `Documents/projects`、现有 SwiftData 模型和 GUI 缓存目录。
- [x] 明确无 schema 变更、失败回滚、UI 可见变化及测试范围。
- [x] 同步 VideoHero 现有 agent automation 文档中的旧结论。

### 阶段 B：项目生命周期实现

- [x] 向 Coordinator 注入 ModelContext。
- [x] 创建并立即保存 automation PPT 项目。
- [x] 将源文件、页面图和缩略图落入项目目录。
- [x] 创建并分阶段保存场景、TTS 和预览缓存。
- [x] 把最终视频保存到项目目录并生成 job artifact 副本。
- [x] 完成失败、取消和重复项目冲突清理。
- [x] 更新 capability。

### 阶段 C：测试和回归

- [ ] 补齐持久化、路径、成功和回滚测试。
- [ ] 运行定向测试。
- [x] 运行 App/CLI Debug 构建。
- [x] 检查现有 GUI 导入和导出代码路径：未修改 `PPTImportService` 或 GUI 导出编排；真实 GUI 回归仍保留在验收项。

### 阶段 D：Skill 和发布文档

- [x] 更新 `SKILL.md` 和 references。
- [x] 更新 README。
- [x] 更新 CHANGELOG。
- [x] 运行 Skill quick validation。
- [x] 整理 WorkBuddy/Qoder 测试命令和人工验收清单。

## 12. 2026-10-19 验证记录

- [x] Release 测试包生成成功：`.build/videohero-agent-testkit-project-persistence-20261019`。
- [x] 测试包中的 App、CLI 签名有效，CLI 包含 team-scoped App Group entitlement。
- [x] 测试包中的 `videohero version --format json` 返回 CLI `0.1.0`、协议 `1`。
- [x] 独立 Skill 仓库通过官方 `quick_validate.py`。
- [ ] 使用真实 PPTX/PDF 和已就绪模型完成一次成片，并验证项目在任务开始后出现、重启后仍可编辑。
- [ ] 使用 WorkBuddy 和 Qoder 分别完成一次 Skill 驱动的真实调用。
