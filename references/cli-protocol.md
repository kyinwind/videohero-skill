# VideoHero CLI protocol reference

This reference describes the intended protocol v1 surface. The installed result of `videohero capabilities --format json` is authoritative. If a command or option below is not advertised, do not use it.

## Discovery and preflight

```bash
videohero version --format json
videohero capabilities --format json
videohero voices list --format json
videohero voices list --engine <engine-id> --format json
videohero models list --format json
videohero doctor --workflow <tts|presentation-to-video> --format json
```

Use exact engine and voice ids returned by discovery. A model marked missing or an engine marked unavailable is a preflight failure; do not begin a long generation and hope that it repairs itself.

## Text-to-speech

Use exactly one of `--text` and `--text-file`. Prefer a UTF-8 text file for multi-paragraph, quoted, shell-sensitive, or private content.

```bash
videohero tts generate \
  --text-file "/absolute/path/script.txt" \
  --output "/absolute/path/narration.wav" \
  --engine <engine-id> \
  --voice <voice-id> \
  --language auto \
  --format json \
  --wait
```

Before submission:

- Confirm the source is not empty.
- Confirm the requested output format is advertised.
- Do not overwrite an existing output without the user's instruction.
- If language is omitted or `auto`, report a language-detection warning from the result rather than hiding it.
- Personal voice ids may require an authorization already completed in VideoHero. Never work around `authorization_required`.

The current P0 implementation advertises WAV only. M4A remains part of the intended v1 surface but must not be requested until `capabilities` advertises it. Confirm the final job state and artifact path; do not infer success from a progress value of 1.0 alone.

## Presentation-to-video

Protocol v1 uses both the PPTX and its matching PDF. The PDF supplies slide rendering; the PPTX supplies body text and speaker notes.

```bash
videohero presentation render \
  --pptx "/absolute/path/deck.pptx" \
  --pdf "/absolute/path/deck.pdf" \
  --output "/absolute/path/deck.mp4" \
  --engine <engine-id> \
  --voice <voice-id> \
  --script-source notes-or-body \
  --aspect source \
  --subtitles burn \
  --format json \
  --wait
```

Before submission:

- Use absolute, readable PPTX and PDF paths.
- Run preflight and require matching slide/page counts.
- `notes-or-body` uses notes when non-empty and otherwise uses extracted body text. Use `notes` only when the user expects empty notes to be an error.
- Obtain supported values from capabilities. The current P0 implementation supports aspect values `source`, `16:9`, `4:3`, and `9:16`, and subtitle values `off` and `burn`. Treat `srt`, `burn-and-srt`, and custom dimensions as unavailable until a future capability response explicitly advertises them.
- Read these values from the structured `presentation` capability object (`narrationSources`, `aspectRatios`, `subtitleModes`, and `videoFormats`); do not infer them from the human-readable `notes` array.
- Treat page-limit or `license_required` results as a user action, not a reason to truncate silently.
- Do not invoke Keynote conversion unless the installed capabilities advertise it and the user has allowed the required macOS automation prompt.

Expected primary artifact is MP4. The current P0 implementation does not return a separate SRT artifact. Preserve and report any warnings returned by the job.

## Jobs and errors

Commands:

```bash
videohero jobs status <job-id> --format json
videohero jobs wait <job-id> --format ndjson
videohero jobs cancel <job-id> --format json
videohero jobs result <job-id> --format json
videohero jobs result <job-id> --overwrite --format json
videohero jobs result <job-id> --output "/absolute/new/path" --format json
```

Terminal states are `succeeded`, `failed`, and `cancelled`. Non-terminal states are expected to include `submitted`, `queued`, `preflighting`, `running`, `finalizing`, and `cancelling`.

`succeeded` means VideoHero generated and verified the staged artifact. Delivery to the user-requested path is tracked separately in the result envelope's `delivery` object. A synchronous command is complete only when `delivery.state` is `delivered` and the process exits with code 0. If delivery fails, preserve the job id and use `jobs result` to retry delivery; do not regenerate the media. Use `--overwrite` only when the user authorized replacing the destination; use `--output` to deliver the same staged artifact to a different absolute path.

JSON/NDJSON on stdout is protocol data. Human diagnostics on stderr are not a replacement for the structured result. Preserve the machine error `code`, user-facing `message`, and any `recovery` object.

Common error handling:

| Code | Agent behavior |
|---|---|
| `input_missing` / `input_invalid` | Recheck the exact input path or ask for a replacement. |
| `pdf_page_mismatch` | Stop; request the PDF exported from the same deck revision. |
| `voice_not_found` | Refresh `voices list`; do not guess a replacement. |
| `model_not_ready` / `helper_not_ready` | Report the advertised recovery action. Install only with user authorization. |
| `license_required` | Stop and tell the user which VideoHero entitlement is required. |
| `authorization_required` | Ask the user to complete the named VideoHero/macOS authorization. |
| `automation_disabled` | Ask the user to enable local agent control in VideoHero settings. |
| `protocol_incompatible` | Stop and request a VideoHero/skill update. |
| `restart_interrupted` | Query artifacts and caches, then offer a retry with the same request and idempotency key. |

For uncertain submission outcomes, query by job id or reuse the same `--idempotency-key`. Never create repeated expensive jobs merely because the waiting process disconnected.
