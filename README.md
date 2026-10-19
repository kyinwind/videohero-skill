# VideoHero Skill

让 Codex、WorkBuddy、Qoder 等智能体通过 VideoHero 官方 CLI 生成语音和带讲解的视频，而不是操作图形界面或访问内部数据库。

## 能力

- 查询 VideoHero、模型、语音引擎和音色能力。
- 将文字生成 WAV 音频。
- 使用匹配的 PPTX/PDF 生成 MP4 讲解视频。
- PPTX/PDF 视频任务默认创建可在 VideoHero 界面继续编辑的项目；无需额外保存参数。
- 文字转语音仍是临时音频任务，不会在项目列表创建记录。
- 查询、等待和取消异步 job。
- 以 NDJSON 持续接收视频生成阶段、百分比和说明。
- 当 VideoHero 有兼容历史样本时，读取预计总耗时和预计剩余时间。
- 校验生成终态与目标路径交付回执。

## 安装

将本仓库目录安装或链接到智能体支持的 Skill 目录，并确保入口文件仍为 `SKILL.md`。具体位置取决于智能体产品；不要只复制 README。

智能体还需要能够执行已安装的 `videohero` CLI。首次使用前，在 VideoHero 的“智能体控制”设置中开启本地智能体操作，并运行：

```bash
videohero version --format json
videohero capabilities --format json
```

## 推荐视频调用方式

先用 JSON 提交并取得 job id：

```bash
videohero presentation render \
  --pptx "/absolute/path/deck.pptx" \
  --pdf "/absolute/path/deck.pdf" \
  --output "/absolute/path/deck.mp4" \
  --engine <engine-id> \
  --voice <voice-id> \
  --format json
```

再以 NDJSON 持续等待：

```bash
videohero jobs wait <job-id> --format ndjson
```

`--format json` 保持单一最终 JSON 文档，不用于实时进度。预计耗时来自相同引擎的本机历史导出；没有历史样本时，job 会正常运行但不会返回 estimate。

视频任务通过预检后会自动创建 VideoHero 项目，生成期间即可在项目列表中看到；成功后可继续编辑。失败或取消会回滚本次项目。已经由旧版 CLI 完成、当时没有写入项目库的历史 job 不会被自动补录，需要使用新版 App/CLI 重新运行。

## 文档

- [CLI 协议参考](references/cli-protocol.md)
- [本地设置与测试](references/setup-and-testing.md)
- [预计耗时与实时进度设计](docs/20261019-cli-video-estimate-and-live-progress.md)
- [CLI 项目持久化设计](docs/20261019-cli-project-persistence.md)

## 安全边界

Skill 不会绕过 VideoHero 授权、私自下载模型、覆盖现有输出或直接修改 VideoHero 的 SwiftData 数据/项目目录。视频项目由 VideoHero App 自己持久化；CLI 超时或等待进程断开不代表 job 失败，应使用原 job id 重新查询。
