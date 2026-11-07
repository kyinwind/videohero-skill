# needs_review 与 export-project（协议 2）

## 背景

此前自动化 PPT 导出只要任一页讲解音频没通过自动质检，整个 job 就以
`narration_quality_failed` 失败。而应用内手动导出会把音频质量问题
（内容不一致 / 声学异常 / 音色漂移）**转人工质检**：保留候选音频、继续跑完其余页、
最后一次性汇总页面清单。

自动化缺少这个承接方式，且没有"审核完继续导出"的入口，智能体在遇到质量问题时无事可做。

## 变更

1. **新增终态 `needs_review`**（`needs_review`），CLI 退出码 **5**：
   - 跑完全部页面后汇总待审页，不产出成片；
   - 返回 `reviewItems` 与 `nextAction`；
   - 属**预期终态**，不是失败。
2. **新增工作流 `export-project`** 与命令
   `videohero presentation export --project <uuid> [--output <path>]`：
   - 复用已生成的讲解音频与页面视频，不重新跑 TTS；
   - 门禁：仍有未审完的页面则再次返回 `needs_review` + 剩余清单；
   - 应用把成片写入自身项目存储，由 CLI 投递到 `--output`（应用是沙盒的）。
3. **协议版本 1 → 2**：终态与工作流枚举均有破坏性扩展，旧 CLI 无法解析 `needs_review`。

## 智能体行为约定

- 收到 `needs_review` / 退出码 5：**不要重试、不要重建项目、不要放宽质检阈值**；
  把 `reviewItems` 原样转告用户，请其在 VideoHero 内完成试听确认。
- 用户确认审核完成后：执行 `presentation export --project <projectId>`；
  若仍返回 `needs_review`，说明还有页面未确认。
- `ASR 不可用` 与 `引擎/资源异常` 不走 `needs_review`，仍属失败（人无法判断"没识别出来"的音频）。

## 兼容性

- 仅支持协议 2；版本不匹配时 `doctor` 会报 `protocol_compatible` 失败，退出码 7。
- 升级顺序：先更新 VideoHero App，再更新 Skill/CLI（二者需同版本）。
