# VideoHero local setup and testing

Use this reference only for local installation, development test kits, or first-run diagnostics.

## Resolve the executable

Prefer an explicit test-kit path when the user supplies one:

```bash
VIDEOHERO_CLI="/absolute/path/to/videohero-agent-testkit/bin/videohero"
"$VIDEOHERO_CLI" version --format json
```

Otherwise resolve the installed command with `command -v videohero`. Do not copy or replace an executable unless the user asked for installation. A VideoHero repository checkout can create a signed test kit with `scripts/prepare_videohero_agent_testkit.sh`; that script packages this independent Skill repository and accepts its path as the second argument or through `VIDEOHERO_SKILL_SOURCE`.

## First run

The current architecture uses the VideoHero App process, not an XPC automation helper. Before testing:

1. Launch the VideoHero app from the same test kit/build as the CLI.
2. In VideoHero settings, open the automation section and enable local agent control.
3. Keep VideoHero running for the first test. A submitted URL may wake the app later, but cold-launch/no-window behavior is not yet a release guarantee.
4. Ensure at least one advertised TTS engine reports both `modelReady` and `helperReady`.

Then run:

```bash
"$VIDEOHERO_CLI" capabilities --format json
"$VIDEOHERO_CLI" models list --format json
"$VIDEOHERO_CLI" voices list --format json
```

Choose only an engine whose readiness fields are true and a voice belonging to that engine. Run `doctor` with the concrete engine, voice, input, and format settings before generation.

## Safe smoke tests

Use new absolute output paths. Do not add `--overwrite` for the first run.

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

Parse the returned job id and follow it with:

```bash
"$VIDEOHERO_CLI" jobs wait <job-id> --format ndjson
```

For presentation testing, use a matching PPTX/PDF pair and run the concrete-input doctor command shown in the protocol reference before `presentation render`. Verify that multiple NDJSON lines arrive while the job is running. If prior exports exist for the selected engine, verify that later lines contain `estimate.estimatedTotalSeconds` and `estimate.estimatedRemainingSeconds`; a first run may legitimately have no estimate.

Also verify project persistence:

1. Confirm `capabilities.presentation.persistsProject` is `true`.
2. After the presentation job starts, confirm a project named from the original PPTX appears in VideoHero before the job succeeds.
3. After success, open the project and confirm its pages, narration, selected engine/voice, subtitle setting, preview caches, and exported video are usable.
4. Restart VideoHero and confirm the project remains available.
5. Run a TTS-only smoke test and confirm it does not create a project-list item.
6. For a disposable presentation job, test cancellation and confirm the incomplete project is removed.

Do not inspect or modify VideoHero's SwiftData files directly. Project-directory inspection is only a developer smoke-test step when the user explicitly asks for local integration testing; normal agents should rely on capabilities, job status, and the VideoHero UI.

## Reporting failures

Return the CLI path, CLI/protocol version, selected engine and voice ids, command exit code, structured error code, job id if one was created, and whether VideoHero was already running. Do not include narration text or private input contents in logs.
