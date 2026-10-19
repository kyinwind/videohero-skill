# VideoHero local setup and testing

Use this reference only for local installation, development test kits, or first-run diagnostics.

## Resolve the executable

Prefer an explicit test-kit path when the user supplies one:

```bash
VIDEOHERO_CLI="/absolute/path/to/videohero-agent-testkit/bin/videohero"
"$VIDEOHERO_CLI" version --format json
```

Otherwise resolve the installed command with `command -v videohero`. Do not copy or replace an executable unless the user asked for installation. A repository checkout can create a signed test kit with `scripts/prepare_videohero_agent_testkit.sh`.

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
  --format json \
  --wait
```

For presentation testing, use a matching PPTX/PDF pair and run the concrete-input doctor command shown in the protocol reference before `presentation render`.

## Reporting failures

Return the CLI path, CLI/protocol version, selected engine and voice ids, command exit code, structured error code, job id if one was created, and whether VideoHero was already running. Do not include narration text or private input contents in logs.
