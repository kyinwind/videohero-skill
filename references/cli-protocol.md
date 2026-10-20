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

### Personal voice discovery

VideoHero exposes the user's authorized “我的声音” with the stable id `videohero.personal-voice.v1`. It may appear once for each compatible engine: `qwen3PresetVoice`, `cosyVoice` when that engine is available on the platform, and `mossTTSNano`. It must not appear for `kokoroTTS`.

Use the id only when the current `voices list --engine <engine-id>` result contains that exact entry. The title is localized and is not an identifier. Absence means the personal voice is unavailable or its Pro/consent/enrollment/reference-audio authorization is incomplete or invalid. The agent may ask the user to finish the “我的声音” flow in VideoHero, but must not perform or bypass that flow. Re-run discovery after the user completes it.

## Text-to-speech

Use exactly one of `--text` and `--text-file`. Prefer a UTF-8 text file for multi-paragraph, quoted, shell-sensitive, or private content.

```bash
videohero tts generate \
  --text-file "/absolute/path/script.txt" \
  --output "/absolute/path/narration.wav" \
  --engine <engine-id> \
  --voice <voice-id> \
  --language auto \
  --format json
```

Parse the returned job id, then wait with `videohero jobs wait <job-id> --format ndjson` when the current turn should follow progress.

Before submission:

- Confirm the source is not empty.
- Confirm the requested output format is advertised.
- Do not overwrite an existing output without the user's instruction.
- If language is omitted or `auto`, report a language-detection warning from the result rather than hiding it.
- The personal voice id `videohero.personal-voice.v1` requires authorization already completed in VideoHero and may be used only with an engine that advertised it. Never work around `authorization_required`.

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
  --format json
```

Parse the returned job id, then stream progress:

```bash
videohero jobs wait <job-id> --format ndjson
```

Before submission:

- Use absolute, readable PPTX and PDF paths.
- Run preflight and require matching slide/page counts.
- `notes-or-body` uses notes when non-empty and otherwise uses extracted body text. Use `notes` only when the user expects empty notes to be an error.
- Obtain supported values from capabilities. The current P0 implementation supports aspect values `source`, `16:9`, `4:3`, and `9:16`, and subtitle values `off` and `burn`. Treat `srt`, `burn-and-srt`, and custom dimensions as unavailable until a future capability response explicitly advertises them.
- Read these values from the structured `presentation` capability object (`narrationSources`, `aspectRatios`, `subtitleModes`, and `videoFormats`); do not infer them from the human-readable `notes` array.
- For “我的声音”, pass `videohero.personal-voice.v1` only after it appears for the selected engine. VideoHero rechecks authorization when the job runs, so a previously discovered voice can still return `authorization_required` if the user later withdraws or loses authorization.
- Treat page-limit or `license_required` results as a user action, not a reason to truncate silently.
- Do not invoke Keynote conversion unless the installed capabilities advertise it and the user has allowed the required macOS automation prompt.

Expected primary artifact is MP4. The current P0 implementation does not return a separate SRT artifact. Preserve and report any warnings returned by the job.

When `capabilities.presentation.persistsProject` is `true`, `presentation render` also creates an editable VideoHero project automatically. The project is created after preflight and is visible in VideoHero while generation is running; successful projects retain their PPTX/PDF, slide images, narration audio, previews, and an internal exported video in VideoHero's managed project storage. No `--save-project` parameter exists or is needed. A failed or cancelled import may be removed using the same cleanup semantics as a failed UI import.

This persistence rule applies only to presentation jobs. `tts generate` remains a temporary audio job and does not add an item to VideoHero's project list.

After VideoHero parses the presentation and resolves narration, status updates may include:

```json
{
  "estimate": {
    "estimatedTotalSeconds": 420,
    "elapsedSeconds": 58,
    "estimatedRemainingSeconds": 362,
    "basedOnRecordCount": 3,
    "updatedAt": "2026-10-19T07:20:00Z"
  }
}
```

Treat this as a historical estimate, not a deadline. Report it with the current stage and percentage when useful. If `estimate` is absent, say that VideoHero does not yet have enough compatible export history; do not calculate a time from `progress` alone.

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

`jobs wait --format ndjson` emits one complete JSON object whenever the observed status changes. Each line can include `stage`, `progress`, `message`, and the optional presentation `estimate`. Parse lines incrementally and surface meaningful changes rather than waiting for EOF. Text mode also streams human-readable updates; `--format json` intentionally emits only one final JSON document and is not a live-progress format.

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
| `authorization_required` | Ask the user to complete or restore the named VideoHero/macOS authorization, then refresh capabilities and `voices list`. Never switch voices silently. |
| `automation_disabled` | Ask the user to enable local agent control in VideoHero settings. |
| `protocol_incompatible` | Stop and request a VideoHero/skill update. |
| `restart_interrupted` | Query artifacts and caches, then offer a retry with the same request and idempotency key. |

For uncertain submission outcomes, query by job id or reuse the same `--idempotency-key`. Never create repeated expensive jobs merely because the waiting process disconnected.
