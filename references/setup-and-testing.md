# VideoHero local setup and testing

Use this reference only for installation, first-run diagnostics, or local integration testing.

## Distribution boundary

The Skill ships the supported standalone CLI at:

```text
bin/macos-universal/videohero
```

The CLI must be a notarized Universal Binary with a hardened Developer ID signature from team `AL7WHQ783W`, the team-scoped Automation App Group entitlement, and no App Sandbox entitlement. The TestFlight App does not contain this CLI. Generation still runs in the VideoHero App process; the CLI is only the external client.

Do not run `VideoHero.app/Contents/MacOS/VideoHero` as the CLI, invoke private helper plug-ins, or search DerivedData, `.build`, old test kits, or the filesystem for alternatives.

## Resolve the executable

Use the first executable in this order and retain its absolute path for the whole workflow:

1. An absolute path explicitly supplied by the user.
2. An absolute `VIDEOHERO_CLI` environment value.
3. The absolute result of `command -v videohero`.
4. `bin/macos-universal/videohero` relative to this Skill root.

Example for the bundled CLI:

```bash
SKILL_ROOT="/absolute/path/to/videohero-skill"
VIDEOHERO_CLI="$SKILL_ROOT/bin/macos-universal/videohero"
"$SKILL_ROOT/scripts/verify.sh" "$VIDEOHERO_CLI"
"$VIDEOHERO_CLI" version --format json
```

If the bundled CLI or `videohero.sha256` is missing, stop and report that the Skill installation is incomplete. Do not fall back to an App-internal or development binary.

## Install into PATH

Only install when the user requests installation or the surrounding task clearly includes it:

```bash
SKILL_ROOT="/absolute/path/to/videohero-skill"
"$SKILL_ROOT/scripts/install.sh"
```

The default destination is `~/.local/bin/videohero`. The script verifies the source, refuses an unrelated destination, copies atomically, and verifies the result. It does not re-sign the binary or remove quarantine. A custom absolute source and destination may be passed as the first and second arguments.

If signature verification fails, or Gatekeeper returns anything other than the documented standalone-CLI “valid code but not an App bundle” note, report the exact output and ask the user to update/re-download the Skill. Do not use `xattr` to bypass the failure.

## First run

1. Install VideoHero through TestFlight or its official distribution channel.
2. Open VideoHero settings and enable local agent control.
3. Keep VideoHero running for the first test.
4. Ensure at least one advertised TTS engine reports both `modelReady` and `helperReady`.
5. Run the resolved CLI once, then run VideoHero's visible basic diagnostics. It should show the CLI version, protocol, path, and last-seen time.

Then query current capabilities:

```bash
"$VIDEOHERO_CLI" capabilities --format json
"$VIDEOHERO_CLI" models list --format json
"$VIDEOHERO_CLI" voices list --format json
```

Choose only a ready engine and a voice belonging to it. Run `doctor` with the concrete engine, voice, input, and output settings before generation.

For a personal-voice test, the user must first complete VideoHero's visible “我的声音” flow. Then verify that `videohero.personal-voice.v1` appears for `qwen3PresetVoice`, `cosyVoice` when available, and `mossTTSNano`, but not for `kokoroTTS`. Do not inspect or copy the underlying reference audio. If the id is absent, report the missing authorization and let the user resolve it in VideoHero before querying again.

## Safe smoke tests

Use new absolute output paths and do not add `--overwrite` for the first run:

```bash
"$VIDEOHERO_CLI" doctor \
  --workflow tts \
  --engine <engine-id> \
  --voice <voice-id> \
  --audio-format wav \
  --format json

"$VIDEOHERO_CLI" tts generate \
  --text "你好，这是 VideoHero 智能体接口测试。" \
  --output "/absolute/new/path/videohero-agent-test.wav" \
  --engine <engine-id> \
  --voice <voice-id> \
  --format json
```

Parse the job id and follow it with:

```bash
"$VIDEOHERO_CLI" jobs wait <job-id> --format ndjson
```

For presentation testing, use a matching PPTX/PDF pair. Confirm that multiple NDJSON lines arrive while running. If compatible export history exists, later events may contain estimated total and remaining seconds; a first run may legitimately have no estimate.

Also verify that a presentation project appears in VideoHero while it is running and remains editable after success. Confirm a TTS-only job creates no project. For a disposable presentation job, test cancellation and confirm the incomplete project is removed.

## Reporting failures

Return the exact CLI path, CLI/protocol version, selected engine and voice ids, command exit code, structured error code, job id if created, and whether VideoHero was already running. Do not include narration text or private input contents in logs.
