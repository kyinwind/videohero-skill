# VideoHero Skill

让 Codex、WorkBuddy、Qoder 等智能体通过 VideoHero 官方 CLI 生成语音和带讲解的视频，而不是操作图形界面或访问内部数据库。

## 能力

- 查询 VideoHero、模型、语音引擎和音色能力。
- 将文字生成 WAV 音频；TTS 是临时任务，不创建项目。
- 使用匹配的 PPTX/PDF 生成 MP4，默认创建并持续保存可编辑的 VideoHero 项目。
- 查询、等待和取消异步 job，以 NDJSON 持续接收阶段、百分比和说明。
- 当 VideoHero 有兼容历史样本时，读取预计总耗时和预计剩余时间。
- 校验生成终态与目标路径交付回执。

## 运行结构

本仓库同时包含 Skill 指令和独立 `videohero` CLI。CLI 负责命令、输入暂存、job 提交、进度读取和产物交付；TTS、PPT/PDF 导入、项目保存和视频生成仍由 TestFlight/正式渠道安装的 VideoHero App 执行。

```text
智能体 → 独立 videohero CLI → Automation App Group → VideoHero App
```

正式 App 包内不包含 agent CLI，也不使用 XPC 自动化 Helper。

## 安装

### 1. 安装 Skill

把整个仓库安装或链接到智能体支持的 Skill 目录，入口文件必须保留为 `SKILL.md`。不要只复制 README 或单独复制可执行文件。

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

### 2. 安装并授权 VideoHero App

通过 TestFlight 或正式渠道安装 VideoHero，在“智能体控制”中开启“允许本地智能体操作 VideoHero”。该开关只负责授权，不负责安装 CLI。

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

## 推荐视频调用方式

先查询 capabilities、models 和 voices，运行具体参数的 doctor，然后提交：

```bash
"$CLI" presentation render \
  --pptx "/absolute/path/deck.pptx" \
  --pdf "/absolute/path/deck.pdf" \
  --output "/absolute/path/deck.mp4" \
  --engine <engine-id> \
  --voice <voice-id> \
  --format json
```

解析返回的 job id，再持续等待：

```bash
"$CLI" jobs wait <job-id> --format ndjson
```

`--format json` 返回单一最终 JSON，不用于实时进度。没有兼容历史样本时，任务会正常运行但不会返回 estimate，智能体不得自行编造时间。

## 文档

- [CLI 协议参考](references/cli-protocol.md)
- [安装与测试](references/setup-and-testing.md)
- [独立 CLI 分发方案](docs/20261019-cli-bundling-and-installation.md)
- [预计耗时与实时进度设计](docs/20261019-cli-video-estimate-and-live-progress.md)
- [CLI 项目持久化设计](docs/20261019-cli-project-persistence.md)

## 安全边界

Skill 不绕过 VideoHero 授权、私自下载模型、覆盖现有输出或直接修改 SwiftData/项目目录。视频项目由 App 持久化；CLI 超时或等待进程断开不代表 job 失败，应使用原 job id 查询。
