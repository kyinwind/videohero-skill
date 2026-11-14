# VideoHero 协议 3 CLI 升级与正式发布方案

日期：2026-11-14

状态：开发完成，待用户使用正式/TestFlight App 验收

## 1. 背景与问题

VideoHero 主工程已经把自动化协议升级到版本 3，并实现项目查询与修改、PPT 只导入、逐页讲解词和图片读写、修改恢复以及 `render-project`。本次升级前，`videohero-skill` 中的正式 CLI 仍报告：

```json
{
  "cliVersion": "0.1.0",
  "protocolVersion": 2
}
```

因此，升级前的 CLI 虽然 Developer ID 签名、公证、双架构和 App Group 均有效，但无法调用协议 3 新能力。当时 skill 本地工作区已开始更新协议 3 文档，二进制尚未同步，存在“文档比可执行程序新”的不一致。

## 2. 需求结论

- 从当前 VideoHero 主工程构建 `arm64 + x86_64` Universal CLI。
- CLI 自身版本从 `0.1.0` 升级为 `0.2.0`，自动化协议必须为 `3`。
- 使用现有 `Developer ID Application: xuehui Yang (AL7WHQ783W)` 正式签名。
- 使用 Keychain 中现有 `videohero-notary` 凭据提交 Apple 公证，只有 `Accepted` 后才更新 skill。
- 发布脚本在替换 skill 二进制前必须校验 CLI 版本、协议版本、架构、签名、时间戳、Team ID、App Group entitlement 和非沙盒属性。
- 更新 `bin/macos-universal/videohero` 与 `videohero.sha256`，不生成本地测试包，不把临时构建产物留在仓库。
- 根据用户发布决定，删除原 GitHub `1.3.3` 标签，并在协议 3 的正式 Skill 提交上重新创建 `1.3.3`；不得让同名标签继续指向协议 2 二进制。

## 3. 技术架构

CLI 仍是 App 外部的薄客户端：

```text
智能体 → Developer ID 签名 CLI（协议 3） → Automation App Group → VideoHero App（协议 3）
```

实际项目导入、持久化、讲解音频生成、质检和视频导出继续由 VideoHero App 执行。CLI 只负责参数解析、输入暂存、job 提交、状态读取和产物交付。

发布流程：

1. 分别构建 arm64 与 x86_64 Release CLI；
2. 使用 `lipo` 合并为 Universal Binary；
3. 对最终 Universal Binary 进行 Developer ID + Hardened Runtime 签名；
4. 验证 `cliVersion == 0.2.0`、`protocolVersion == 3`；
5. 验证 Team ID、Automation App Group、非沙盒 entitlement 和安全时间戳；
6. 压缩并提交 Apple 公证；
7. 公证 `Accepted` 后原子更新 skill 二进制和 SHA-256；
8. 对发布副本再次执行完整验签与版本验证。

同一已签名归档在 Apple 公证 API 出现瞬时网络中断时最多重试 3 次；重试期间不重新签名、不改变二进制。三次均失败则退出且不更新 skill。

裸 Mach-O CLI 不能像 `.app` 一样附加公证票据。macOS 的 `spctl` 可能返回“not an app”或 `source=Unnotarized Developer ID`；在同一发布流程已经得到 Apple `Accepted` 且严格代码签名验证通过时，这两类结果只作说明，不覆盖公证结论。

## 4. 数据库与持久化变化

**无数据库变更。**

本任务只升级外部 CLI 和 skill 发布内容，不修改 VideoHero 的 SwiftData schema，也不新增项目字段。协议 3 的项目编辑快照和项目数据规则已经由 VideoHero 主工程实现，本次不重复修改。

持久化变化仅包括：

- 替换 skill 中受 Git 管理的 CLI 二进制；
- 更新对应 SHA-256 清单；
- 更新 skill 文档和版本记录。

无需数据库迁移，旧项目兼容性由 VideoHero App 现有协议 3 实现负责。

## 5. 界面变化与国际化

**无用户界面变更。**

不新增或修改 SwiftUI 页面、按钮、诊断结果和错误提示，因此本任务没有新增中英文界面资源。验收时仍需确认 CLI 的结构化输出没有影响 App 现有中英文界面。

## 6. 修改范围

### VideoHero 主工程

- `VideoHeroCLI/main.swift`
  - CLI 版本升级为 `0.2.0`。
- `scripts/build_videohero_cli_release.sh`
  - 发布前后校验 CLI `0.2.0` 与协议 `3`，防止发布旧二进制。

### videohero-skill

- `bin/macos-universal/videohero`
  - 更新为协议 3、CLI 0.2.0 的正式签名 Universal Binary。
- `bin/macos-universal/videohero.sha256`
  - 更新发布二进制校验和。
- `SKILL.md`、`README.md`、`CHANGELOG.md`
  - 保留并核对协议 3 的能力、限制和版本说明。
- `agents/openai.yaml`
  - 更新技能入口说明，移除独立文字转语音表述并加入项目管理能力。
- `references/cli-protocol.md`
  - 核对协议 3 命令及错误处理。
- `references/parameter-selection.md`
  - 核对项目导入和渲染时的引擎/音色选择规则。
- `references/setup-and-testing.md`
  - 核对版本匹配、安装和烟雾测试说明。
- `docs/20261114-protocol3-cli-release.md`
  - 本需求、架构、开发计划和验证记录。

不预计新增其他代码文件。

## 7. 风险与对策

### 协议错配

协议 3 CLI 不能与协议 2 App 混用。Skill 继续要求以 VideoHero 正式版本标签匹配，`protocolVersion` 作为最终兼容依据。

### 签名或公证失败

发布脚本在任何签名、entitlement、公证或发布副本复验失败时不替换 skill 中的权威 CLI。公证网络请求只对同一签名归档进行最多 3 次有限重试，不能无限提交。

`spctl` 是面向 App bundle 的评估，不作为裸 Mach-O CLI 的公证权威来源；Apple `notarytool` 的 `Accepted` 与 `codesign --verify --strict --all-architectures` 才是硬门槛。

### 重建已发布标签

用户已明确要求重建 `1.3.3`。发布时先提交完整代码、文档和正式 CLI，再删除旧的本地及远端标签，并在新提交上创建带说明的 `1.3.3` 标签；推送后核对远端标签与本地提交一致。已经检出旧标签的使用者需要执行 `git fetch --tags --force` 获取新标签。

### 文档与二进制不一致

发布前后都解析 `videohero version --format json`，强制校验 CLI 版本和协议版本；skill 验证同时检查 SHA-256 和正式签名。

## 8. 测试与验收计划

- CLI Release arm64 和 x86_64 构建成功。
- Universal Binary 同时包含 `arm64`、`x86_64`。
- `version --format json` 返回 CLI `0.2.0`、协议 `3`。
- `codesign --verify --strict --all-architectures` 通过。
- Developer ID、Hardened Runtime、安全时间戳、Team ID 与 Automation App Group 校验通过。
- Apple 公证结果为 `Accepted`。
- skill `scripts/verify.sh --require-checksum` 通过。
- skill-creator `quick_validate.py` 通过。
- `git diff --check` 在两个仓库均通过。
- 使用协议 3 App 做真实验收：`capabilities`、`projects list`、`projects get`、页面读取和 dry-run 更新至少各成功一次。

## 9. 开发计划

### 阶段 A：分析与文档

- [x] 确认 skill 当前 CLI 为协议 2、CLI 0.1.0。
- [x] 确认 VideoHero 当前源码协议为 3，并包含新项目/页面命令。
- [x] 明确数据库、持久化、界面、签名、公证和标签边界。
- [x] 写入本升级方案。

### 阶段 B：版本与发布保护

- [x] 将 CLI 版本升级为 0.2.0。
- [x] 发布脚本增加 CLI 版本和协议 3 硬校验。
- [x] 发布脚本增加同一签名归档的有限公证网络重试。
- [x] 适配 macOS 27.2 对裸 Mach-O CLI 的说明性 `spctl` 结果。
- [x] 完成代码检查和 CLI 双架构编译。

### 阶段 C：正式签名与公证

- [x] 使用 Developer ID Application 签名最终 Universal CLI。
- [x] 验证 Hardened Runtime、时间戳、Team ID、App Group 和非沙盒属性。
- [x] Apple 公证状态达到 `Accepted`。
- [x] 原子更新 skill CLI 和 SHA-256。

### 阶段 D：Skill 与验收

- [x] 核对协议 3 的 SKILL、README、CHANGELOG、智能体入口元数据和 references。
- [x] 运行 skill 发布验证和 skill-creator 校验。
- [x] 运行两个仓库的 `git diff --check`。
- [x] 补充验证记录，将状态更新为待用户真实验收。

### 阶段 E：用户正式版本验收

- [ ] 用户打包并安装包含协议 3 的 VideoHero 正式/TestFlight 版本。
- [ ] 使用新 CLI 完成协议 3 项目查询、页面读取和 dry-run 修改验证。
- [ ] 删除旧 `1.3.3`，在本次协议 3 提交上重建并推送同名标签。

## 10. 实施与验证记录

2026-11-14 已完成以下发布验证：

- CLI 版本：`0.2.0`。
- 自动化协议：`3`。
- 架构：`x86_64 arm64`。
- 签名：`Developer ID Application: xuehui Yang (AL7WHQ783W)`。
- Hardened Runtime、安全时间戳、Team ID `AL7WHQ783W`、Automation App Group entitlement 和非沙盒属性均通过校验。
- Apple 公证结果：`Accepted`，submission ID 为 `136daa96-142a-40a2-932c-96bf58248846`。
- 发布二进制 SHA-256：`af8142ac574391adb97ab48eae1cba7c3660124c865ac99ec3df8fdb9a211206`。
- `scripts/verify.sh --require-checksum` 通过。
- skill-creator `quick_validate.py` 通过。
- VideoHero 与 videohero-skill 两个仓库的 `git diff --check` 通过。
- CLI 帮助已确认包含 `projects list/get/update/restore`、`presentation import/render-project` 和 `presentation pages apply`。

本记录只证明 CLI 构建、签名、公证、发布副本和静态协议入口符合要求。协议 3 App 的真实项目读写与页面修改仍需用户安装新的正式/TestFlight 版本后完成阶段 E 验收。

