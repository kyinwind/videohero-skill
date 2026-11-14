---
name: videohero
description: Operate the local VideoHero app through its supported CLI to discover capabilities, import and inspect PPT projects, rewrite per-page narration or slide images, convert narration into structured multi-speaker dialogue, update safe project settings, render narrated videos, and monitor jobs. Before a new import or render, the user must explicitly choose the TTS engine and voice. Do not use for standalone text-to-speech, direct database access, generic media tools, or UI-click automation.
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

If the bundled executable or checksum is missing, report that the installed Skill is incomplete and ask the user to update it; do not search elsewhere. When the user asks to install the command into PATH, read the setup reference and use this Skill's `scripts/install.sh`. If automation is disabled, explain that separate condition. If the reported protocol is incompatible, tell the user the installed Skill does not match the VideoHero app version: each Skill tag is named after the app version. If no tag exists for the app version (currently anything below 1.3.2), ask the user to update VideoHero to 1.3.2 or later first; otherwise check out the tag matching the app version, then refresh capabilities. Do not substitute guessed commands, another binary, or a different protocol version. The expected stable protocol is version 3 (older clients are no longer supported).

## Workflow

1. Read the current capabilities instead of relying on remembered engines, voices, formats, or defaults.
2. **Collect the engine and the voice from the user before presentation rendering.** Read [references/parameter-selection.md](references/parameter-selection.md). This step applies to `presentation render` and cannot be skipped:
   - If the user has not explicitly named both an engine and a voice, do not submit; a CLI fallback is not a choice. Show **every enabled** engine from `capabilities.ttsEngineIDs` (id, readiness, voice count), then **every** voice of the engine the user picks, and wait for the answer.
   - Engines that VideoHero has not enabled for users are not choices: never display or submit them, even when `capabilities` still advertises them. `mingTTS` (Ming-3.0-TTS) is currently not enabled.
   - Show the complete lists: never truncate, shortlist, reorder into “recommended”, pre-select, or silently substitute.
   - If the user gave only one of the two, ask only for the missing one. If the user delegates the choice (“随便”, “you decide”), propose one concrete engine + voice pair and wait for confirmation.
   - A voice title is not an identifier; resolve it only after the full voice list is shown, and let the user confirm which engine it belongs to.
3. Validate the chosen pair from discovery: `videohero voices list --engine <engine-id> --format json` must contain the voice `id`, and `videohero doctor --workflow presentation-to-video --engine <engine-id> --voice <voice-id> --format json` must pass before expensive generation. Include the presentation input and output parameters when the installed CLI supports them, and pass `--subtitles burn` so preflight checks the subtitle mode you will submit.
   For “我的声音”/personal voice, use `videohero.personal-voice.v1` only when `voices list` returns it for the selected engine. Its absence means it is unavailable or not currently authorized; do not infer it from the title or substitute another engine silently.
4. Submit the operation with absolute paths and `--format json` without `--wait`, then parse the returned job id. Prefer `--text-file` for long or sensitive text. Always pass the engine and voice the user chose.
5. For a returned job id, use `videohero jobs wait <job-id> --format ndjson` when the user wants the current turn to wait; otherwise report the job id and use `jobs status` later. During presentation jobs, relay meaningful stage/progress changes and an `estimate` when present. An absent estimate means VideoHero has insufficient compatible history; never invent a completion time. Use `jobs cancel` only when the user requests cancellation or the current task explicitly authorizes it.
6. Treat success as confirmed only when the final state is `succeeded`, `delivery.state` is `delivered`, and the CLI exits with code 0. Return the receipt's actual `destinationPath` and any warnings.
7. A presentation job may end in `needs_review` (CLI exit code 5). This is a **terminal and expected** outcome, not a failure: VideoHero generated the narration but some pages need the user to listen and confirm in the app. Do not retry, do not rebuild the project, and do not raise the automatic retry limit. Relay the returned `pages` list so the user knows exactly which pages need review, and tell them to finish the review in VideoHero.
8. After the user confirms the review is done, continue with `videohero presentation export --project <projectID> --output <path>`. It reuses the already generated narration and never regenerates it. If any page is still unapproved, that command also returns `needs_review` with the remaining pages and exits with code 5.
9. For editing an existing project, query it first with `projects get` and `presentation pages get`. Preserve returned revisions and page digests in every update. Use `--dry-run` before multi-page or settings mutations. Never retry a conflict with stale revisions; query again and reconcile the user's intent.
10. Dialogue conversion is semantic work performed by the agent. Submit structured `speakers` and `turns`; do not rely on literal labels such as `张三说：`. Keep turn text free of speaker labels and use only voice ids advertised for the project's current engine.
11. Page images may be read or replaced only through `presentation pages`. A replacement must be PNG/JPEG, declare its exact SHA-256, and match the project's aspect ratio. Never write the project directory directly.

Presentation rendering creates and continuously saves an editable VideoHero project by default when `capabilities.presentation.persistsProject` is true. Do not add or invent a `--save-project` option. The CLI does not provide standalone text-to-speech or audio-file generation. Never write VideoHero's SwiftData store or project directory yourself; the App owns persistence.

Engine and voice are the only presentation-generation settings you must never default. Every other presentation parameter keeps its documented default — `language=auto`, `script-source=notes-or-body`, `aspect=source`, `subtitles=burn`, `--format json`, and an output path derived from the input file name. Pass `--subtitles burn` explicitly because the CLI's own fallback is `off`; the remaining defaults may be omitted. State the defaults you used in the submission summary. Never choose an engine or voice on the user's behalf, and never retry with a materially different engine or voice without asking again. `presentation export` reuses the project's existing engine and voice and needs no new choice.

Do not download models, accept licenses, enable agent control, authorize a personal voice, overwrite an existing output, or retry a failed generation with materially different settings unless the user has authorized that action. A timeout is not evidence that submission failed: query the job or retry with the same idempotency key.

## Routes

- For choosing the engine and voice (required before generation), read [references/parameter-selection.md](references/parameter-selection.md).
- For PPTX/PDF-to-video, read [references/cli-protocol.md](references/cli-protocol.md#presentation-to-video).
- For project, narration, dialogue, and slide-image editing, read [references/cli-protocol.md](references/cli-protocol.md#project-and-page-editing).
- For job states, structured errors, recovery, or cancellation, read [references/cli-protocol.md](references/cli-protocol.md#jobs-and-errors).
- When the user asks to install, configure, or test the local integration, read [references/setup-and-testing.md](references/setup-and-testing.md).

Keep paths as separate command arguments. Do not interpolate user text into shell syntax. When a request is complex, write a versioned request JSON supported by `capabilities` and pass its path rather than assembling a fragile command line.
