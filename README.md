# VideoHero Skill

让 Codex、WorkBuddy、Qoder 等智能体通过 VideoHero 官方 CLI 管理 PPT 视频项目、改写逐页讲解词和图片，并生成带讲解的视频，而不是操作图形界面或访问内部数据库。

## 选择与 VideoHero 版本一致的 Skill

本仓库的 **tag 名称对应 VideoHero App 版本**，CLI 与 App 通过版本化协议通信。安装、升级 Skill 时，
必须使用与当前 App 版本相同的 tag；不要混用 `main`、旧 tag，或手工替换 `bin/macos-universal/videohero`。

先确认 App 版本（VideoHero → “关于 VideoHero”），或直接读取：

```bash
defaults read /Applications/VideoHero.app/Contents/Info.plist CFBundleShortVersionString
```

App 不在 `/Applications` 时替换为实际路径。以 `CFBundleShortVersionString` 为准，不看 build number。

新克隆时直接检出同名 tag（示例为 `1.3.3`）：

```bash
git clone --branch 1.3.3 --depth 1 https://github.com/kyinwind/videohero-skill.git
```

已有仓库时切换 tag：

```bash
git fetch --tags --force
git checkout 1.3.3
```

`--force` 用于更新被重建的 tag；本地已有旧的同名 tag 时，普通的 `git fetch --tags`
会拒绝覆盖，必须用上面的命令重新拉取。

验证 CLI 与 App 的协议一致：

```bash
./bin/macos-universal/videohero version --format json
```

`protocolVersion` 才用于判断兼容性（当前为 3）；`cliVersion` 是 CLI 自身版本，不参与判断。
版本不匹配时，`capabilities` 会解码失败，或 `doctor` 报 `protocol_compatible` 失败（退出码 7）：
此时切到同名 tag 或升级 App，不要手工替换二进制。

tag 名是入口，`protocolVersion` 是最终依据。如果某个 tag 的 CLI 与 App 协议不一致，说明该 tag
未正确配套：不要手工修改，改用能与 App 协议配对的 tag，并向维护者反馈该 tag。

- `1.3.3` 使用 CLI 0.2.0、协议 3，包含项目与页面自动化能力；`1.3.1` 的 Skill 已撤回，App `1.3.1` 及更早版本请先升级。
- `main` 是最新开发状态，可能领先于已发布 App，只用于开发联调。
- 如果 App 版本没有同名 tag，说明该版本尚未配套发布 Skill；不要用邻近 tag 顶替：`1.3.1` 及更早请升级 App，
  更新的版本请等待对应 tag。
- 升级顺序：先升级 VideoHero App，再把 Skill 切到同名 tag，并重新运行 `scripts/verify.sh`
  （安装到 PATH 时再运行 `scripts/install.sh`）。

## 能力

- 查询 VideoHero 版本、协议、模型、语音引擎和音色能力。
- 生成前要求用户显式选择引擎与音色：展示全部候选，用稳定 ID 提交。
- 在用户已于 VideoHero 完成授权时，发现并使用“我的声音”生成 PPT 视频。
- 使用匹配的 PPTX/PDF 生成 MP4，默认创建并持续保存可编辑的 VideoHero 项目。
- 查询和修改项目名称、分辨率、字幕、字体、引擎、音色与生成风格。
- 读取或原子回写指定页面的讲解词、结构化多人对话、图片和页面设置，并支持恢复一次修改。
- 查询、等待和取消异步 job，以 NDJSON 持续接收阶段、百分比和说明。
- 当 VideoHero 有兼容历史样本时，读取预计总耗时和预计剩余时间。
- 支持 `needs_review` 人工质检终态；在 App 内确认后可用 `presentation export` 复用讲解音频续跑导出。
- 校验生成终态与目标路径交付回执。

## 运行结构

本仓库同时包含 Skill 指令和独立 `videohero` CLI。CLI 负责命令、输入暂存、job 提交、项目/页面修改、进度读取和产物交付；PPT/PDF 导入、项目保存、讲解音频生成、质检和视频生成仍由 TestFlight/正式渠道安装的 VideoHero App 执行。

```text
智能体 → 独立 videohero CLI → Automation App Group → VideoHero App
```

正式 App 包内不包含 agent CLI，也不使用 XPC 自动化 Helper。

## 安装

### 1. 安装 Skill

先按上一节切换到与 App 版本相同的 tag。把整个仓库安装或链接到智能体支持的 Skill 目录，入口文件必须保留为 `SKILL.md`。不要只复制 README 或单独复制可执行文件，也不要从其它 tag 的目录借用 CLI。

权威 CLI 路径为：

```text
<videohero-skill>/bin/macos-universal/videohero
```

智能体可以直接使用该绝对路径。若需要从 PATH 调用，在仓库根目录运行：

```bash
./scripts/verify.sh
./scripts/install.sh
```

默认安装到：

```text
~/.local/bin/videohero
```

安装脚本会先验证 SHA-256、Developer ID 签名、安全时间戳、Hardened Runtime、Team ID、Automation App Group、Universal 架构和 CLI 版本，再原子复制。Apple 公证状态已验证为 `Accepted`；`spctl` 对裸 Mach-O CLI 返回“有效代码但不是 App”时显示说明而不误判失败。Apple Development 构建只用于开发机联调，不能作为公开发布版本。安装过程不会现场重签、删除 quarantine 或覆盖无法确认的其他工具。

`1.3.3` 所带 CLI 为 `0.2.0`、协议 `3`，已使用 `Developer ID Application: xuehui Yang (AL7WHQ783W)` 正式签名并通过 Apple 公证。

安装到 PATH 的 CLI 是该 tag 的副本；升级 App 后要重新切换 tag 并重新安装。

### 2. 安装并授权 VideoHero App

通过 TestFlight 或正式渠道安装 VideoHero（版本必须与 Skill tag 一致），在“智能体控制”中开启“允许本地智能体操作 VideoHero”。该开关只负责授权，不负责安装 CLI。

首次使用时建议保持 App 运行，然后执行：

```bash
CLI="/videohero-skill/绝对路径/bin/macos-universal/videohero"
"$CLI" version --format json
"$CLI" capabilities --format json
```

运行一次 CLI 后，VideoHero 的基础诊断会显示外部 CLI 版本、路径和最后连接时间。

### 3. CLI 发现顺序

智能体必须依次尝试：

1. 用户明确提供的绝对路径；
2. 绝对路径形式的 `VIDEOHERO_CLI`；
3. PATH 中的 `videohero`；
4. 当前 Skill 的 `bin/macos-universal/videohero`。

不得扫描 DerivedData、`.build`、旧测试包或 `/Applications/VideoHero.app` 内部，也不得调用 App 主程序和私有模型 Helper 代替 CLI。

### 4. 升级

App 升级后，旧 tag 的 Skill/CLI 会变成旧协议。切换到新的同名 tag 后重新验证：

```bash
git fetch --tags
git checkout <新版本>
./scripts/verify.sh
./scripts/install.sh   # 仅当 CLI 已安装到 PATH
```

如果新版本 App 暂时没有同名 tag，建议暂缓升级 App，等待 Skill 发布对应 tag。

## 引擎与音色必须由用户明确指定

生成 PPT 视频之前，智能体必须让用户在**全部已启用引擎**里选一个引擎，再在该引擎的**全部音色**里选一个音色，
并用稳定 ID 提交。未启用的引擎不展示、也不作为选项。不允许让 CLI 兜底的音色值、历史任务或“看起来合适”替用户决定：

```text
capabilities（全部已启用引擎 + 就绪状态 + 音色数）
voices list --engine <选中的引擎>（该引擎全部音色，含“我的声音”）
用户确认 engine id + voice id
doctor → presentation render
```

其余参数（脚本来源、画面比例、字幕、语言、输出路径等）在用户未指定时使用默认值，并在提交摘要中声明。
CLI 自身的字幕缺省是 `off`，Skill 默认生成字幕，所以提交时应显式传 `--subtitles burn`。
`presentation export` 复用项目既有引擎和音色，不再询问。完整规则见
[引擎与音色选择](references/parameter-selection.md)。

## 推荐视频调用方式

先查询 capabilities、models 和 voices，按上面的补参流程拿到用户确认的 engine 与 voice，运行具体参数的 doctor，然后提交：

```bash
"$CLI" doctor --workflow presentation-to-video \
  --pptx "/absolute/path/deck.pptx" \
  --pdf "/absolute/path/deck.pdf" \
  --output "/absolute/path/deck.mp4" \
  --engine <engine-id> \
  --voice <voice-id> \
  --subtitles burn \
  --format json

"$CLI" presentation render \
  --pptx "/absolute/path/deck.pptx" \
  --pdf "/absolute/path/deck.pdf" \
  --output "/absolute/path/deck.mp4" \
  --engine <engine-id> \
  --voice <voice-id> \
  --subtitles burn \
  --format json
```

解析返回的 job id，再持续等待：

```bash
"$CLI" jobs wait <job-id> --format ndjson
```

`--format json` 返回单一最终 JSON，不用于实时进度。没有兼容历史样本时，任务会正常运行但不会返回 estimate，智能体不得自行编造时间。

- 成功：终态为 `succeeded`，且 `delivery.state` 为 `delivered`，读取实际 `destinationPath` 和警告。
- `needs_review`（退出码 5）：讲解已生成，但部分页面需要用户在 App 内试听确认。不要重试、不要重建项目；
  把待审页面转告用户，等其在 VideoHero 完成质检后执行：

```bash
"$CLI" presentation export --project <project-id> --output "/absolute/path/deck.mp4"
```

`presentation export` 复用已生成的讲解音频，不重新生成 TTS；仍有未确认页面时会再次返回 `needs_review`。

## 智能体修改现有项目

先查询项目和页面，保留返回的修订令牌与摘要：

```bash
"$CLI" projects list --format json
"$CLI" projects get --project <project-id> --format json
"$CLI" presentation pages get --project <project-id> \
  --pages 1,3-5 --include body,notes,script,image \
  --output-dir "/absolute/path/page-images" --format json
```

项目设置和页面内容都通过 JSON 请求文件修改。多页修改先执行 `--dry-run`，确认后再使用最新修订正式提交：

```bash
"$CLI" projects update --project <project-id> --request "/absolute/project-update.json" --dry-run --wait --format json
"$CLI" presentation pages apply --project <project-id> --request "/absolute/pages-update.json" --dry-run --wait --format json
```

正式写入成功后会返回 `editID`，可分别用 `projects restore` 或 `presentation pages restore` 恢复。图片必须匹配项目画面比例；多人对话应提交结构化 `speakers` 与 `turns`，不要把“张三说：”等标签混入台词正文。补生成缺失音频并执行完整质检与视频导出时使用：

```bash
"$CLI" presentation render-project --project <project-id> --output "/absolute/path/deck.mp4" --wait --format json
```

## 使用“我的声音”

先在 VideoHero 的“我的声音”界面完成 Pro 校验、声音使用同意、登记和验证，然后按引擎查询：

```bash
"$CLI" voices list --engine qwen3PresetVoice --format json
```

只有返回列表中存在稳定 ID `videohero.personal-voice.v1` 时才能将它传给 `--voice`。当前支持 Qwen3 TTS、CosyVoice（平台公开时）和 MOSS-TTS Nano，KokoroTTS 不支持；实际以 `voices list --engine <id>` 的返回为准。Skill 和 CLI 不会替用户接受协议、登记声音或读取个人参考音频；若返回 `authorization_required`，应让用户回到 VideoHero 完成或恢复授权后重新查询。

## 文档

- [CLI 协议参考](references/cli-protocol.md)
- [引擎与音色选择](references/parameter-selection.md)
- [安装与测试](references/setup-and-testing.md)
- [版本匹配约定](docs/20261108-version-matched-skill-tags.md)
- [引擎与音色显式选择设计](docs/20261108-engine-voice-explicit-selection.md)
- [独立 CLI 分发方案](docs/20261019-cli-bundling-and-installation.md)
- [预计耗时与实时进度设计](docs/20261019-cli-video-estimate-and-live-progress.md)
- [CLI 项目持久化设计](docs/20261019-cli-project-persistence.md)
- [CLI“我的声音”支持设计](docs/20261020-cli-personal-voice.md)
- [协议 3 CLI 升级与正式发布方案](docs/20261114-protocol3-cli-release.md)

## 安全边界

Skill 不绕过 VideoHero 授权、私自下载模型、覆盖现有输出或直接修改 SwiftData/项目目录。视频项目由 App 持久化；CLI 超时或等待进程断开不代表 job 失败，应使用原 job id 查询。收到 `needs_review` 时不得重试或放宽质检，必须由用户在 App 内确认。
