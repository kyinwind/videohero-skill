# VideoHero 独立 CLI 随 Skill 分发：需求分析、技术架构和开发计划

> 日期：2026-10-19  
> 状态：独立分发、Developer ID 签名、Apple 公证和权威 CLI 发布已完成，等待 TestFlight 与智能体端到端验收  
> 涉及仓库：VideoHero、videohero-skill  
> 勾选规则：只有实际完成并验证的项目才标记为 `- [x]`

## 1. 决策与目标

VideoHero 采用“沙盒 App + 独立非沙盒 CLI”的交付方式：

- `VideoHero.app` 继续通过 TestFlight / Mac App Store 渠道交付并保持 App Sandbox。
- `videohero` CLI 不再嵌入 `VideoHero.app/Contents/Helpers`，避免 App Store Connect 要求包内可执行文件启用沙盒，也避免沙盒 CLI 无法读取用户指定 PPTX、PDF 和输出目录。
- CLI 使用 Developer ID Application 签名、Hardened Runtime 和 Apple 公证，作为独立可执行文件随 `videohero-skill` 发布。
- CLI 只负责参数验证、输入暂存、提交作业、唤醒 App、持续读取进度及交付产物；TTS、PPT/PDF 导入、项目持久化和视频生成仍由 VideoHero App 执行。
- 不新增 XPC、后台 Helper、LaunchAgent 或常驻服务。

目标结构：

```text
videohero-skill/
├── SKILL.md
├── bin/macos-universal/videohero   # 已签名、公证的权威 CLI
└── scripts/
    ├── install.sh
    └── verify.sh

~/.local/bin/videohero              # 安装后的独立副本
/Applications/VideoHero.app         # TestFlight 安装的沙盒 App
```

## 2. 功能需求

### 2.1 VideoHero App

- [x] App 构建不再把 `videohero` 复制到 `Contents/Helpers`；正式 Archive 由用户发布时复验。
- [x] arm64 Release App 产物不包含外部 agent CLI；最终上传包仍待 TestFlight 验收。
- [x] App 保留 Automation App Group、URL Scheme、作业执行器和现有业务 workflow。
- [x] “智能体控制”设置页不再显示“App 内置 CLI”，也不再创建指向 App 包内文件的符号链接。
- [x] 设置页显示最近连接的外部 CLI 路径、CLI/协议版本、最后连接时间和兼容性。
- [x] 基础诊断继续显示可见结果，并区分“尚未运行外部 CLI”“CLI 路径失效”“协议不兼容”和“可用”。

### 2.2 独立 CLI

- [x] 保留现有 `VideoHeroCLI` Xcode target，但不作为 App target 的依赖或嵌套代码。
- [x] Release CLI 使用 `arm64 + x86_64` Universal Binary。
- [x] 独立 CLI 不启用 App Sandbox。
- [x] CLI 保留 team-scoped Automation App Group entitlement，以便与同一 Team ID 的 VideoHero App 交换作业。
- [x] 已用 Developer ID Application 身份完成 CLI 签名，并验证 Hardened Runtime、安全时间戳、Team ID 与 Automation App Group。
- [x] Apple 公证返回 `Accepted`，并验证 `codesign`、架构、版本和协议；裸 Mach-O CLI 的 `spctl` “not an app”仅作平台行为记录。
- [x] 私钥、证书和公证凭据未写入 Git 仓库、skill 或脚本默认值；离线备份由用户在仓库外保管。

### 2.3 Skill 分发与安装

- [x] skill 仓库包含一份已签名、公证的权威 CLI，不包含 DerivedData、临时测试包或旧版本副本。
- [x] `scripts/install.sh` 默认把 CLI 原子复制到 `~/.local/bin/videohero`，不得创建指向 Git checkout 的长期符号链接。
- [x] 安装前校验源 CLI 的签名、Team ID、App Group entitlement、架构和可执行权限。
- [x] 安装不得静默覆盖普通文件、目录或未知工具；更新仅覆盖可确认是 VideoHero CLI 的现有文件。
- [x] 安装后再次校验目标并运行 `videohero version --format json`。
- [x] 智能体优先解析用户显式绝对路径，再解析 `VIDEOHERO_CLI`、PATH，最后解析 skill 自带 CLI；不得扫描 DerivedData、`.build` 或全盘碰运气。
- [x] App 与 CLI 通过 `protocolVersion` 做兼容检查；不兼容时明确提示更新 VideoHero 或 skill。

## 3. 技术架构

### 3.1 运行时链路

```text
Codex / WorkBuddy / Qoder
        ↓
独立 videohero CLI（非沙盒、Developer ID）
        ↓ 暂存输入、写 request、唤醒 App、读取 events
Automation App Group
        ↓
VideoHero App（TestFlight、App Sandbox）
        ↓ 创建项目、TTS、字幕、PPT/PDF 处理、视频导出
App Group artifact → CLI 原子交付到用户目标路径
```

CLI 与 App 的职责边界不变。独立分发只改变 CLI 的安装和签名方式，不把生成引擎移出 App。

### 3.2 Xcode 与签名

`VideoHeroCLI` target 继续复用 `SharedAutomation` 协议代码，构建设置调整为：

- `ENABLE_APP_SANDBOX = NO`
- `ENABLE_HARDENED_RUNTIME = YES`
- `CODE_SIGN_ENTITLEMENTS = VideoHeroCLI/VideoHeroCLI.entitlements`
- Release 发布构建使用 Developer ID Application；TestFlight App Archive 不依赖或嵌入该 target。

CLI entitlement 只保留 Automation App Group。App Archive 与 CLI 发布是两个独立流程。skill 安装脚本不得现场重签 CLI；安装机器不应持有开发者私钥。

### 3.3 安装与发现

CLI 解析顺序：

1. 用户明确提供的绝对路径；
2. 绝对路径形式的 `VIDEOHERO_CLI`；
3. `command -v videohero`；
4. 当前 skill 根目录下的 `bin/macos-universal/videohero`。

如果找到 skill 内 CLI，智能体可以直接调用，也可以在用户要求安装时运行 `scripts/install.sh`。安装目标默认是 `~/.local/bin/videohero`，无需管理员权限。

skill 内不得再引用 `/Applications/VideoHero.app/Contents/Helpers/videohero`，因为正式 App 不再包含该文件。

### 3.4 发布与更新

开发者发布脚本负责：

1. 构建 `arm64`、`x86_64` Release CLI并用 `lipo` 合并。
2. 使用 Developer ID Application 身份和 CLI entitlement 签名。
3. 生成 ZIP 并提交 `notarytool`，等待公证成功。
4. 验证公证状态、签名、安全时间戳、Hardened Runtime、Team ID、entitlement、架构、版本和协议。`spctl --type execute` 对裸 Mach-O CLI 返回“有效代码但不是 App”时只记录说明；其他评估错误仍阻止发布。
5. 把 CLI 复制到 skill 临时目标，重新执行校验和、严格验签、架构、entitlement 和版本检查；全部通过后再原子更新权威 CLI 及 SHA-256 清单。

发布时的签名身份和公证凭据只从 Keychain/CI secret 读取，不进入仓库。用户自行保管的证书离线备份也不属于 skill 产物。

## 4. 数据库与持久化

**无数据库 schema 变更。**

本需求只改变 CLI 的交付、签名、安装和发现方式。现有 SwiftData 模型、`VHProject`、`VHScene`、项目目录结构以及 CLI 演示文稿项目持久化规则保持不变，不需要迁移旧数据。

- Automation App Group 中现有 `cli-registration-v1.json` 继续记录外部 CLI 的实际路径、版本、协议和最后连接时间。
- 旧 App 内 CLI 路径可能留在注册文件中；诊断显示原路径不可用，等待外部 CLI 下一次运行后自然刷新。
- CLI 安装状态由文件系统判断，不写入 SwiftData。

## 5. 界面变化

“智能体控制”页面：

- 删除“App 内置 CLI”状态、App 包内路径、“安装命令入口”“卸载”和“复制 App 内 CLI 路径”。
- 保留授权开关和基础诊断。
- 显示“外部 CLI 随 VideoHero Skill 安装，首次运行后这里会显示连接状态”。
- 最近连接存在且路径可执行、协议匹配时显示成功；未连接、路径失效或协议不兼容时给出明确提示。
- 所有诊断结果保持页面内可见，不依赖无反馈 toast。

## 6. 预计代码变更

### 6.1 VideoHero

- `VideoHero.xcodeproj/project.pbxproj`：删除 App → CLI 依赖、嵌入阶段和签名脚本 CLI 输入；CLI target 改回非沙盒独立产物。
- `VideoHeroCLI/VideoHeroCLI.entitlements`：删除 App Sandbox，保留 Automation App Group。
- `scripts/sign_embedded_helpers.sh`：删除嵌入 CLI 签名逻辑。
- `VideoHero/View/Settings/VideoHeroAutomationSettingsView.swift`：删除 App 内 CLI 安装 UI，保留外部 CLI 注册诊断。
- `README.md`、`CHANGELOG.md` 以及 `docs/agent-automation/` 下的需求、架构、计划和测试指南。
- 删除仅服务旧方案的 `VideoHero/Automation/VideoHeroCLIInstallationService.swift` 和 `VideoHeroTests/VideoHeroCLIInstallationServiceTests.swift`。
- 可能新增 `scripts/build_videohero_cli_release.sh`，负责独立 CLI 构建、签名、公证和发布。

### 6.2 videohero-skill

- `SKILL.md`
- `README.md`
- `CHANGELOG.md`
- `references/setup-and-testing.md`
- `scripts/install.sh`
- `scripts/verify.sh`
- `bin/macos-universal/videohero`
- CLI SHA-256 清单文件（具体名称在实现时确定）

## 7. 风险与对策

- **Developer ID 与 App Group**：发布和安装阶段均检查 Team ID 与 entitlement；安装只复制，不重签。
- **公证与 quarantine**：发布前公证；安装脚本不得删除 quarantine 绕过 Gatekeeper，只报告验证失败和重新下载方式。
- **裸 CLI 的 Gatekeeper 输出**：Apple 公证以 `notarytool` 的 `Accepted` 为权威结果；`spctl` 是面向 App/安装包的评估工具，裸 CLI 的 “not an app”不等同于未公证。
- **发布副本完整性**：公证通过不代表后续复制绝不会损坏；发布脚本在 skill 临时目标重新严格验签，验证失败时保留原权威 CLI 并终止发布。
- **App/CLI 版本错配**：以协议版本判断兼容性；不兼容时停止提交并指出更新 App 或 skill。
- **多个 CLI 导致误发现**：skill 只保留一个权威路径，删除测试包和全盘扫描说明。
- **Intel slice 未实机验证**：检查 `lipo -archs`，并在可用 Intel 环境补充运行验收。

## 8. 开发与验证计划

### 阶段 A：文档

- [x] 记录行业方案比较和最终架构决策。
- [x] 明确数据库、界面、代码文件、风险和测试范围。
- [x] 同步 VideoHero 主仓库需求、架构、开发计划和测试指南。
- [x] 更新 README 与 CHANGELOG。

### 阶段 B：移除 App 内嵌 CLI

- [x] 删除 App 对 CLI 的构建依赖和复制阶段。
- [x] 删除嵌入 CLI 重签逻辑及 App 包内 CLI 安装服务。
- [x] 将 CLI entitlement 和 target 恢复为独立非沙盒模式。
- [x] 验证 arm64 Release App 产物中不存在 `Contents/Helpers/videohero`；正式 Archive 仍待验收。
- [ ] 验证 App 构建、单元测试和签名不受影响。

### 阶段 C：独立 CLI 发布工具链

- [x] 编写 Universal CLI 构建、Developer ID 签名、公证和发布脚本。
- [x] 缺少签名或公证凭据时脚本直接失败，不会假装发布成功。
- [x] 验证 CLI Developer ID 签名、时间戳、Team ID、App Group、Hardened Runtime 和双架构。
- [x] 把最终签名、公证 CLI 更新到 skill 权威路径并生成 SHA-256 清单。

### 阶段 D：Skill 安装与发现

- [x] 新增安全安装和验证脚本。
- [x] 更新 SKILL、README、setup reference 和 CHANGELOG。
- [x] 删除 App 内 CLI、Release test kit 和开发目录扫描说明。
- [x] 运行 skill quick validation。
- [x] 从干净临时目录验证安装、更新和冲突保护。

### 阶段 E：端到端验收

- [ ] 用户 Archive 并上传 TestFlight，确认不再出现包内 CLI 沙盒错误。
- [ ] TestFlight 安装版与 skill CLI 完成 `version`、`capabilities`、`doctor`。
- [ ] 用 WorkBuddy/Qoder 提交 TTS 并验证音频产物。
- [ ] 用 WorkBuddy/Qoder 提交 PPTX + PDF 视频任务，验证预计时间、持续进度、项目列表和最终视频。
- [ ] 验证 App 未运行时的唤醒行为以及失败/取消后的恢复。

## 9. 验收标准

- [ ] TestFlight 归档包内不存在 `Contents/Helpers/videohero`，App Store Connect 上传通过。
- [x] skill 中只有一份权威 CLI，且为签名有效、公证通过的 Universal Binary。
- [ ] CLI 可以读取用户指定输入文件、写入用户指定输出位置并访问 Automation App Group。
- [ ] CLI 与 TestFlight App 可以提交任务、输出预计时间、持续输出进度并交付结果。
- [ ] CLI 演示文稿任务沿用 GUI 项目持久化；TTS 保持临时任务。
- [ ] 设置页明确显示外部 CLI 未连接、可用、失效和协议不兼容状态。
- [ ] 不新增 XPC、后台 Helper、LaunchAgent 或 SwiftData migration。
