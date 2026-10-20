---
name: videohero
description: Operate the local VideoHero app through its supported CLI to discover voices and models, generate speech from text, render PPTX/PDF presentations as narrated videos, and monitor or cancel VideoHero jobs. Use when a user asks an agent to create media with VideoHero; do not use for generic media tools or UI-click automation.
---

# VideoHero

Use VideoHero only through its supported `videohero` CLI. Do not automate the SwiftUI interface, edit VideoHero's SwiftData store, call its private helper executables, or construct files inside its project directories.

This Skill ships the supported standalone CLI at `bin/macos-universal/videohero`. The CLI is a thin client; the VideoHero App still performs generation. Enabling local agent control in VideoHero authorizes automation but does not install the CLI. Do not treat the GUI executable or bundled private speech helpers as substitutes.

Resolve the CLI executable in this order: an absolute path supplied by the user; an absolute `VIDEOHERO_CLI`; `command -v videohero`; then `bin/macos-universal/videohero` relative to this `SKILL.md`. Resolve the bundled path to an absolute path before invoking it. Do not scan DerivedData, `.build`, old test kits, App bundles, or arbitrary private executables. Keep using the first executable absolute path for the whole workflow. Start with:

```bash
CLI="/absolute/path/to/videohero"
"$CLI" version --format json
"$CLI" capabilities --format json
```

If no absolute path was supplied, try each supported source in order and verify it is executable before use.

If the bundled executable or checksum is missing, report that the installed Skill is incomplete and ask the user to update it; do not search elsewhere. When the user asks to install the command into PATH, read the setup reference and use this Skill's `scripts/install.sh`. If automation is disabled or the reported protocol is incompatible, explain that separate condition. Do not substitute guessed commands. The expected first stable protocol is version 1.

## Workflow

1. Read the current capabilities instead of relying on remembered engines, voices, formats, or defaults.
2. Run `videohero doctor --workflow <workflow> --format json` before expensive generation. For a concrete request, include its input and output parameters when the installed CLI supports them.
3. Resolve the requested voice from `videohero voices list --format json`. Use its stable `id`, not its localized title. If the user's description matches multiple voices, present the meaningful candidates instead of choosing silently.
   For “我的声音”/personal voice, use `videohero.personal-voice.v1` only when `voices list` returns it for the selected engine. Its absence means it is unavailable or not currently authorized; do not infer it from the title or substitute another engine silently.
4. Submit the operation with absolute paths and `--format json` without `--wait`, then parse the returned job id. Prefer `--text-file` for long or sensitive text.
5. For a returned job id, use `videohero jobs wait <job-id> --format ndjson` when the user wants the current turn to wait; otherwise report the job id and use `jobs status` later. During presentation jobs, relay meaningful stage/progress changes and an `estimate` when present. An absent estimate means VideoHero has insufficient compatible history; never invent a completion time. Use `jobs cancel` only when the user requests cancellation or the current task explicitly authorizes it.
6. Treat success as confirmed only when the final state is `succeeded`, `delivery.state` is `delivered`, and the CLI exits with code 0. Return the receipt's actual `destinationPath` and any warnings.

Presentation rendering creates and continuously saves an editable VideoHero project by default when `capabilities.presentation.persistsProject` is true. Do not add or invent a `--save-project` option. Text-to-speech remains a temporary audio job and must not create a VideoHero project. In both cases, never write VideoHero's SwiftData store or project directory yourself; the App owns persistence.

Do not download models, accept licenses, enable agent control, authorize a personal voice, overwrite an existing output, or retry a failed generation with materially different settings unless the user has authorized that action. A timeout is not evidence that submission failed: query the job or retry with the same idempotency key.

## Routes

- For text-to-speech, read [references/cli-protocol.md](references/cli-protocol.md#text-to-speech).
- For PPTX/PDF-to-video, read [references/cli-protocol.md](references/cli-protocol.md#presentation-to-video).
- For job states, structured errors, recovery, or cancellation, read [references/cli-protocol.md](references/cli-protocol.md#jobs-and-errors).
- When the user asks to install, configure, or test the local integration, read [references/setup-and-testing.md](references/setup-and-testing.md).

Keep paths as separate command arguments. Do not interpolate user text into shell syntax. When a request is complex, write a versioned request JSON supported by `capabilities` and pass its path rather than assembling a fragile command line.
