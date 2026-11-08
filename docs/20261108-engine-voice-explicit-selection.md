# 引擎与音色显式选择（补参机制）

- 日期：2026-11-08
- 状态：已实施
- 影响文件：`SKILL.md`、`references/cli-protocol.md`、`references/parameter-selection.md`（新增）、`README.md`、`CHANGELOG.md`、`agents/openai.yaml`

## 背景

当前 Skill 只要求智能体“读 capabilities，不要凭记忆”，并要求从 `voices list` 取稳定音色 ID，
但没有规定**引擎和音色必须由用户选择**。CLI 已把 `--engine` 设为必填（缺省会报
`缺少必需参数 --engine`），但 `--voice` 仍可缺省：缺省时回落到该引擎 `availableVoices.first`。
于是智能体可以自行挑一个引擎、或用默认音色直接提交，用户直到拿到成片才知道用了什么。

而这两个恰恰是本次生成最关键、返工成本最高的决策：

1. 引擎决定模型是否已下载、内存占用、速度、音质，以及“我的声音”是否可用；
2. 音色决定成片听感，且音色按引擎隔离，同一套预制音色标题在多个引擎下都存在；
3. 音色标题是本地化显示名，不是稳定标识，不能作为隐式默认的依据；
4. 智能体一旦凭记忆或历史默认引擎/音色，用户很可能拿到“不是我想要的声音”。

因此需要一个明确的“补参”机制：**引擎与音色由用户显式指定，其余参数使用默认值**。

## 目标与非目标

目标：

- 任何 `tts generate` / `presentation render` 提交之前，引擎和音色都必须有用户显式给出的值；
- 智能体必须把 `capabilities` 里已启用的全部引擎、以及所选引擎的全部音色完整展示给用户；未启用的引擎不展示；
- 引擎与音色之外的其他参数沿用默认值，并在提交摘要里声明；
- 宿主无法向用户提问时，智能体停在“待补参”状态并返回清单，不得用默认值开跑。

非目标：

- 不修改 CLI 参数、协议版本、job 结构或持久化格式；
- 不删除 CLI 侧的缺省能力（其他调用方仍可能依赖，删除属破坏性变更）；
- 不在本次为 capabilities 增加引擎显示名字段；
- 不在本次修改 App 的 capabilities 声明；未启用引擎由 Skill 侧过滤；
- 不改变 `presentation export` 复用项目既有引擎/音色的语义。

## 参数分级

| 级别 | 参数 | 规则 |
|---|---|---|
| A 用户决策（无默认） | `--engine`、`--voice` | 用户未显式给出 → 必须停下来展示候选并询问；不得由智能体自行挑选、CLI 音色缺省值、历史、记忆或“看起来合理”推断 |
| B 可默认 | `--language`（auto，跟随所选音色）、`--script-source`（notes-or-body）、`--aspect`（source）、`--subtitles`（burn）、音频格式（wav）、`--speed`（1.0）、`--format`（json）、输出路径（由输入同名推导） | 用户未指定 → 直接采用默认，并在提交摘要中声明 |
| C 需用户授权 | `--overwrite`、下载模型、接受许可、个人声音授权、取消 job、换参数重试、把 PPTX 转成 PDF | 不得自动执行 |

B 级“默认”是 Skill 统一采用的固定值，与应用界面默认一致；其中 `--subtitles burn` 必须显式传入
——CLI 自身的缺省是 `off`，省略会得到无字幕成片。`--script-source`、`--aspect`、`--language`、
`--speed` 可以省略。

输入材料（`--pptx` + 匹配的 `--pdf`，或 `--text` / `--text-file`）没有默认值，属于同一轮补参：
缺失时一次性问清，不要先提交再失败。

## 交互契约

### 1. 识别缺口

- 先从用户消息里找：引擎（稳定 id 或明确的引擎名）与音色（稳定 id 或唯一标题）；
- 两项都已显式给出且能在 discovery 结果中校验 → 不重复询问；
- 只缺一项 → 只补问缺少的那一项；
- 用户说“随便 / 你决定 / 用默认的”不等于显式指定（见第 5 条）；
- 不允许“用户没说 → 用 CLI 默认”这条路径。

### 2. 展示全部已启用引擎

用一轮消息展示 `capabilities` 里已启用的完整引擎集合，逐行包含：序号、引擎（id + 可读名）、
就绪状态（`engineReadiness.modelReady` / `helperReady` 与 `issues` 摘要）、该引擎音色数量。

- 已启用但暂时不可用的引擎也要列出，并说明需要下载模型或修复运行时；
- 未启用的引擎不展示、也不作为选项；当前 `mingTTS`（Ming-3.0-TTS）未启用，即使 capabilities 仍声明也要过滤；用户点名该引擎时说明未启用，并给出已启用引擎；
- 不标注“默认”或“推荐”，避免引导用户跳过决策；只有用户主动要建议时才给建议并说明依据；
- 引擎可读名只是展示层映射（见 `references/parameter-selection.md`），权威标识始终是 id；
  未知 id 原样展示，不得臆造。

### 3. 展示全部音色

用户选定引擎后，执行 `videohero voices list --engine <engine-id> --format json`，
把返回的每一项都列出来：序号、音色标题、稳定 ID、语言。

- 包括 `videohero.personal-voice.v1`（当它出现在结果里时）；
- 不抽样、不截断、不重排成“精选”，不预选；
- 用户直接报音色名时：在所有引擎的候选中列出全部同名 / 同 id 组合，由用户确认引擎；
- 音色属于哪个引擎以 `voices list` 返回的 `engineID` 为准。

未启用的引擎（当前 `mingTTS`）已从全部展示模板移除，并在 `SKILL.md` / `references/parameter-selection.md` 中要求过滤，即使 capabilities 仍声明也不展示、不可提交。

### 4. 确认后提交

- 用用户确认的两个 id 执行
  `doctor --workflow <tts|presentation-to-video> --engine <id> --voice <id> --format json`；
  presentation 还要带上实际提交的 `--subtitles burn` 等参数；
- 提交命令显式带上 `--engine` 和 `--voice`；
- 给用户的提交摘要必须回显：引擎、音色，以及本次采用的默认参数（脚本来源、比例、字幕、语言等）；
- 生成过程中不得替换引擎或音色；换引擎必须重新确认音色（音色按引擎隔离）。

### 5. 用户委托选择

“你决定 / 随便 / 用默认”不构成显式指定：

- 智能体给出一个具体组合（引擎 + 音色）和理由，请用户确认；
- 只有用户明确说“直接开始、不用再确认”时，才可代为选择；
- 即使代选，提交摘要也要写明最终组合，并告诉用户如何更改。

### 6. 无法交互的宿主

如果当前宿主不能在本轮向用户提问：

- 不提交生成；
- 返回完整引擎清单 + 下一轮所需信息（选定引擎后才能列出音色）；
- 给出可直接复用的命令模板与“请指定 `--engine` / `--voice`”的说明；
- 绝不以默认值开跑。

### 7. 异常与重问

| 情况 | 处理 |
|---|---|
| 选定引擎不可用（模型缺失 / helper 异常） | 报告 issues，给出“换引擎”和“授权下载模型”两条路，不静默替换引擎 |
| `voice_not_found` | 重新拉该引擎全量音色后重问，保留已选引擎 |
| 个人声音 `authorization_required` | 说明需在 VideoHero 完成授权，保留已选引擎与音色意向，不换引擎 |
| 用户中途改引擎 | 展示新引擎全部音色并重新确认 |
| 音色在 job 运行时失效 | 报告失败与原因，回到音色列表重选，不自动换一个 |

## 展示格式

引擎表：

| 序号 | 引擎 | 引擎 ID | 状态 | 音色数 |
|---|---|---|---|---|
| 1 | Qwen3 TTS | qwen3PresetVoice | 就绪 | 19 |
| 2 | CosyVoice | cosyVoice | 就绪 | 19 |
| 3 | MOSS-TTS Nano | mossTTSNano | 就绪 | 28 |
| 4 | KokoroTTS | kokoroTTS | 就绪 | 45 |

音色表（选定引擎后）：

| 序号 | 音色 | 音色 ID | 语言 |
|---|---|---|---|
| 1 | 我的声音 | videohero.personal-voice.v1 | zh |
| 2 | 温柔邻家女声 | F0_温柔邻家女声 | zh |
| … | … | … | … |

提问模板：

> 请指定引擎和音色（回复序号或 ID 即可）。音色需要先定引擎，所以我先列出引擎。
> 其余参数我会用默认：脚本来源 notes-or-body、画面比例 source、字幕 burn、语言 auto。

上表中的数量只是示例，实际数量必须以 `capabilities` / `voices list` 为准。

## 验收场景（待人工验收）

以下为智能体行为场景，需在接入 Skill 的宿主里逐条人工验收；本轮只验证了 CLI 发现与 doctor 行为。

- [ ] “把 deck.pptx 转成视频”但未指定引擎 / 音色：智能体展示全部已启用引擎并停下，不提交；选定引擎后再展示该引擎全部音色。
- [ ] 未启用引擎（Ming-3.0-TTS）不出现在引擎表或任何列表中，即使 capabilities 声明。
- [ ] 用户已给出引擎 + 音色：不重复询问，doctor 校验后直接提交，摘要回显两者。
- [ ] 用户只给引擎：只展示该引擎全部音色，不重复展示引擎。
- [ ] 用户只给音色：列出包含该音色的全部引擎，请用户确认。
- [ ] 用户说“随便”：给出具体组合并等待确认；只有明确“不用确认”才代选。
- [ ] 用户指定不可用引擎：报告原因，不静默换引擎。
- [ ] 个人声音：仅当 `voices list --engine <id>` 返回该 id 时使用；未授权时保留引擎并请用户去 App 授权。
- [ ] `presentation export`：不重新询问引擎 / 音色。
- [ ] 无交互宿主：返回清单与命令模板，不生成。
- [ ] TTS 路径与 presentation 路径规则一致。

## 兼容性与回滚

- 纯 Skill 指令改动：无协议、job、磁盘格式变化，旧 App / CLI 不受影响；
- CLI 侧只在 `--voice` 上保留缺省值（`--engine` 已必填），因此这仍是智能体行为约束，不是完整的 CLI 硬门禁；
- 回滚：还原 `SKILL.md`、`references/cli-protocol.md`，删除新增 reference 与本文档，同步回滚 README / CHANGELOG。

## 后续可选项（本次不做）

- `capabilities` 增加 `engineName`，让智能体不必依赖展示层映射；
- 若需要硬门禁，可让 CLI 在缺少 `--voice` 时也拒绝提交（`--engine` 已是必填）；
  这会破坏现有缺省调用，需单独评审与版本升级。
- `capabilities` 暴露“用户可见/已启用”标志，或由 App 侧停止声明未启用引擎，Skill 就不需要维护过滤名单。

## 验证

用仓库内 CLI（重新构建后为 protocol 2）对本机 App 实测：

- `capabilities --format json` 声明 5 个引擎，其中 `mingTTS` 未启用；按规则过滤后应向用户展示 4 个已启用引擎：
  `qwen3PresetVoice`、`cosyVoice`、`mossTTSNano`、`kokoroTTS`，均就绪；
- `voices list --engine <id>` 实测音色数：Qwen3 19、CosyVoice 19、MOSS 28、Kokoro 45；
  `videohero.personal-voice.v1` 只在已授权的 Qwen3 / CosyVoice / MOSS 结果里出现，Kokoro 不出现；
- `doctor --workflow tts --voice F0_温柔邻家女声`（不带 `--engine`）返回
  `voice_requires_engine`，退出码 2；
- `tts generate --text ... --output ...`（不带 `--engine`）返回 `invalid_request`
  “缺少必需参数 --engine”，退出码 2，证明引擎必须显式给出；
- `doctor --workflow tts --engine qwen3PresetVoice --voice F0_温柔邻家女声` 返回
  `engine_exists`、`engine_ready`、`voice_available`，退出码 0；
- `doctor --workflow presentation-to-video --engine qwen3PresetVoice --voice F0_温柔邻家女声 --subtitles burn --script-source notes-or-body --aspect source` 全部通过，退出码 0；
- 文档内相对链接均可解析，SKILL.md 不再保留“用默认引擎/音色”的表述。

CLI 与 App 必须同为协议 2；本机仓库内二进制已更新，发布时仍需重新校验签名与校验和。

## 实施清单

- [x] 设计文档
- [x] `SKILL.md` 工作流与参数边界
- [x] `references/parameter-selection.md`
- [x] `references/cli-protocol.md`
- [x] `README.md`
- [x] `CHANGELOG.md`
- [x] 文档内链接与一致性检查
