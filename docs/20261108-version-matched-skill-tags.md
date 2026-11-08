# Skill tag 与 VideoHero 版本一一对应

- 日期：2026-11-08
- 状态：已实施
- 影响文件：`README.md`、`SKILL.md`、`references/setup-and-testing.md`、`CHANGELOG.md`、本文档

## 背景

本仓库同时分发 Skill 指令和独立 `videohero` CLI，CLI 与 VideoHero App 通过版本化协议通信。
仓库曾发布 `1.3.1`、`1.3.2` 两个 tag，tag 名与 VideoHero App 的
`CFBundleShortVersionString` 一致；`1.3.1` 已撤回，只保留 `1.3.2`。README 原来只教“安装/链接仓库”，没有说明：

- 必须先确认 App 版本，再使用同名 tag；
- `main` 可能领先于已发布 App，不能默认用于生产；
- App 版本没有同名 tag 时没有配套 Skill；
- 协议不匹配时怎么判断、先升级哪一端。

用户按 `main` 或旧 tag 安装后，CLI 可能出现 `capabilities` 解码失败、
`doctor` 报 `protocol_compatible`（退出码 7）等问题，却看不出是版本不匹配。

另外实测发现：`1.3.1` tag 的 SKILL/CHANGELOG 已声明协议 2，但打包的 CLI 仍是协议 1；
`1.3.2` tag 才同时满足文档与二进制。因此不能只按 tag 名信任，安装后必须验证
`protocolVersion`。

## 决策

1. **tag 名 = VideoHero App 版本**（以 `CFBundleShortVersionString` 为准，不看 build number）。
   当前只发布 `1.3.2`；`1.3.1` 已撤回，App `1.3.1` 及更早版本需先升级到 `1.3.2` 或更高。
   示例：App `1.3.2` → Skill tag `1.3.2`。同名 tag 仍须通过 `protocolVersion` 验证（见第 5、7 条）。
2. **安装、升级、以及接入智能体的 Skill 目录都必须是对应 tag 的完整仓库**，
   不能混用 `main`、其它 tag 的目录，或手工替换 `bin/macos-universal/videohero`。
3. **`main` 只用于开发联调**，可能领先于最新发布的 App。
4. **App 版本没有同名 tag 时，该版本没有配套 Skill**：不要用邻近 tag 顶替；
   `1.3.1` 及更早请先升级 App 到 `1.3.2` 或更高，更新的版本等待对应 tag。
5. **兼容性以 `protocolVersion` 判断**：`videohero version --format json` 的
   `cliVersion` 是 CLI 自身版本，不能用来判断；`capabilities.protocolVersion` /
   `doctor` 的 `protocol_compatible` 才是权威检查。
6. **升级顺序**：先升级 VideoHero App，再把 Skill 切到同名 tag，重新
   `scripts/verify.sh`（需要安装到 PATH 时再 `scripts/install.sh`）。
7. **tag 内的 CLI 也必须验证**：安装后运行 `version --format json`，`protocolVersion`
   与 App 不一致的 tag 视为未正确配套；不改写已发布 tag，反馈后重新发版或重打。

## 文档改动

README 新增“选择与 VideoHero 版本一致的 Skill”一节，包含：

- 查看 App 版本的命令（`defaults read ... CFBundleShortVersionString`）；
- 新克隆与已有仓库切换 tag 的命令；
- `main` 的定位与“无同名 tag”的处理；
- 版本不匹配的表现与退出码；
- 升级顺序与 `protocolVersion` 的说明。

同时把 README 其余内容更新到协议 2 现状：

- 能力列表补充“显式选择引擎/音色”“`needs_review` 人工质检”“`presentation export` 续跑导出”；
- 推荐调用流程改为“doctor → render → jobs wait → 成功或 `needs_review` → export”；
- “我的声音”支持引擎列表与当前启用状态一致；
- 安装步骤强调先切到同名 tag，并补充升级小节；
- 说明 `1.3.1` 已撤回、App 1.3.1 及更早版本需升级到 1.3.2 以上。

`references/setup-and-testing.md` 增加版本匹配说明，并同步个人声音支持的引擎范围。

`SKILL.md` 在协议不兼容时明确指向版本匹配：告知用户安装/检出与 App 版本同名的 tag，
不得换用其它二进制或篡改协议版本。

## 兼容性与回滚

- 纯文档改动，不涉及协议、job、持久化或二进制；
- 本次撤回 `1.3.1`，并把 `1.3.2` 重建为最新 Skill 代码；`1.3.1` 不再提供，App 1.3.1 及更早需升级；
- 回滚：还原 README / setup reference / CHANGELOG，删除本文档，恢复原 tag（如仍需要）。

## 验收

- [x] README 中 `git clone --branch <version>`、`git checkout <version>` 命令可直接执行；
- [x] 版本检查命令在本机能读出 `1.3.2`；
- [x] `git tag --sort=-v:refname` 只列出 `1.3.2`（`1.3.1` 已撤回）；
- [x] `videohero version --format json` 返回 protocol 2，与当前 App 一致；
- [x] README 与 setup reference 对个人声音支持的引擎描述一致；
- [x] Markdown 相对链接与锚点全部可解析。

## 验证记录

- `defaults read /Applications/VideoHero.app/Contents/Info.plist CFBundleShortVersionString` → `1.3.2`；
- `git tag --sort=-v:refname` → 仅 `1.3.2`（`1.3.1` 已撤回）；
- `git clone --branch 1.3.2 --depth 1 https://github.com/kyinwind/videohero-skill.git` 成功，
  克隆内 CLI `version` → protocol 2；
- 当前仓库 CLI `version` → protocol 2，与已安装 App 1.3.2 一致；
- 按 README 的完整 `doctor` 示例（含 PPTX/PDF/输出路径/引擎/音色/`--subtitles burn`）执行通过，退出码 0；
- 撤回前实测 `1.3.1` tag 内 CLI 为 protocol 1，与文档声明的协议 2 不符，已撤回；
  重建后的 `1.3.2` tag 内 CLI 为 protocol 2；
- README 与 setup reference 链接、锚点检查通过。

## 实施清单

- [x] 设计文档
- [x] README 版本匹配章节
- [x] README 协议 2 内容更新
- [x] `references/setup-and-testing.md`
- [x] `CHANGELOG.md`
- [x] 撤回 `1.3.1`、重建 `1.3.2` tag
- [x] 链接与一致性检查
