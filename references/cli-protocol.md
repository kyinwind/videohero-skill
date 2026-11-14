# VideoHero CLI protocol reference

This reference describes the protocol v3 surface. The installed result of `videohero capabilities --format json` is authoritative. If a command or option below is not advertised, do not use it.

## Discovery and preflight

```bash
videohero version --format json
videohero capabilities --format json
videohero voices list --format json
videohero voices list --engine <engine-id> --format json
videohero models list --format json
videohero doctor --workflow presentation-to-video --format json
```

Use exact engine and voice ids returned by discovery. A model marked missing or an engine marked unavailable is a preflight failure; do not begin a long generation and hope that it repairs itself.

### Engine and voice are user choices

`--engine` and `--voice` are **required user decisions** for
`presentation render`, not agent defaults. The CLI requires `--engine` but lets `--voice` fall
back to the engine's first voice; neither is the user's choice. Before submitting, show every
engine VideoHero enables for users (filter out not-enabled engines such as `mingTTS` even when
`capabilities` lists them), and then every voice from `voices list --engine <engine-id>`, and
wait for an explicit choice. See
[parameter-selection.md](parameter-selection.md) for the full interaction contract, display
format, and edge cases.

Only these two parameters are gated. Every other presentation parameter keeps its documented default and
must not be turned into a question: `language=auto`, `script-source=notes-or-body`,
`aspect=source`, and an output path derived from the input.
`subtitles=burn` is the Skill default and must be passed explicitly, because the CLI's own
fallback is `off`. `presentation export` reuses the project's existing engine and voice.

If `--voice` is supplied without `--engine`, `doctor` reports `voice_requires_engine`; that is
the CLI's own guard, not permission to add an engine by assumption.

### Personal voice discovery

VideoHero exposes the user's authorized “我的声音” with the stable id `videohero.personal-voice.v1`. It may appear once for each compatible engine: `qwen3PresetVoice`, `cosyVoice` when that engine is available on the platform, and `mossTTSNano`. It must not appear for `kokoroTTS`.

Use the id only when the current `voices list --engine <engine-id>` result contains that exact entry. The title is localized and is not an identifier. Absence means the personal voice is unavailable or its Pro/consent/enrollment/reference-audio authorization is incomplete or invalid. The agent may ask the user to finish the “我的声音” flow in VideoHero, but must not perform or bypass that flow. Re-run discovery after the user completes it.

## Presentation-to-video

Protocol v3 uses both the PPTX and its matching PDF. The PDF supplies slide rendering; the PPTX supplies body text and speaker notes.

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

- Confirm `--engine` and `--voice` are the user's explicit choice (see [Engine and voice are user choices](#engine-and-voice-are-user-choices)).
- Use absolute, readable PPTX and PDF paths.
- Run preflight and require matching slide/page counts.
- `notes-or-body` uses notes when non-empty and otherwise uses extracted body text. Use `notes` only when the user expects empty notes to be an error.
- Obtain supported values from capabilities. The current P0 implementation supports aspect values `source`, `16:9`, `4:3`, and `9:16`, and subtitle values `off` and `burn`. Treat `srt`, `burn-and-srt`, and custom dimensions as unavailable until a future capability response explicitly advertises them.
- Read these values from the structured `presentation` capability object (`narrationSources`, `aspectRatios`, `subtitleModes`, and `videoFormats`); do not infer them from the human-readable `notes` array.
- For “我的声音”, pass `videohero.personal-voice.v1` only after it appears for the selected engine. VideoHero rechecks authorization when the job runs, so a previously discovered voice can still return `authorization_required` if the user later withdraws or loses authorization.
- Treat page-limit or `license_required` results as a user action, not a reason to truncate silently.
- Do not invoke Keynote conversion unless the installed capabilities advertise it and the user has allowed the required macOS automation prompt.

Expected primary artifact is MP4. The current P0 implementation does not return a separate SRT artifact. Preserve and report any warnings returned by the job.

### Import without rendering

```bash
videohero presentation import --pptx <pptx> --pdf <pdf> --engine <id> [--voice <id>] [--wait] --format json
```

This creates an editable project and returns its `projectID` without generating narration or video. Engine and voice still must be selected explicitly because later dialogue and rendering are validated against that engine.

## Project and page editing

```bash
videohero projects list --format json
videohero projects get --project <uuid> --format json
videohero projects update --project <uuid> --request <project-update.json> [--dry-run] [--wait] --format json
videohero projects restore --project <uuid> --edit <edit-id> [--wait] --format json

videohero presentation pages get --project <uuid> [--pages 1,3-5] [--include body,notes,script,image] [--output-dir <dir>] [--wait] --format json
videohero presentation pages apply --project <uuid> --request <pages-update.json> [--dry-run] [--idempotency-key <key>] [--wait] --format json
videohero presentation pages restore --project <uuid> --edit <edit-id> [--wait] --format json
videohero presentation render-project --project <uuid> --output <mp4> [--overwrite] [--wait] --format json
```

Always read before writing. Project updates require the latest `expectedSettingsRevision`; page updates should carry `expectedSettingsRevision`, `expectedContentRevision`, and each edited page's `expectedTextDigest`/`expectedImageDigest`. A conflict means the project changed: do not overwrite it or mechanically retry. Query again and reconcile the user's requested change.

Page narration accepts either plain content or structured dialogue. Structured dialogue defines stable speaker ids and voice ids separately from ordered turns. Do not include speaker labels in turn text. VideoHero compiles turns into native UTF-16 voice ranges and validates every voice against the project's current engine.

For image reads, include `image` and provide `--output-dir`. For image writes, the JSON request points to an absolute local `sourcePath` and declares its SHA-256. The CLI stages the file; VideoHero accepts only decodable PNG/JPEG within its safety limits and with the same aspect ratio as the project. Image-only edits invalidate previews but retain narration audio and subtitle alignment.

Successful non-dry-run mutations return an `editID`. Restore commands restore the corresponding VideoHero-managed snapshot. Never edit project or snapshot files directly.

`render-project` generates missing or invalid narration, applies the normal quality gates, and may return `needs_review`. `presentation export` is only for projects whose narration is already valid; otherwise it returns `project_requires_render`.


### Presentation export

```
videohero presentation export --project <project-id> [--output <path>] [--overwrite] [--wait] [--format json]
```

Exports an existing VideoHero project without regenerating narration. Use it after a `needs_review` outcome has been fully reviewed in the app. The command is gated: if any page still awaits manual review it returns `needs_review` with the remaining `reviewItems` and exits with code 5. Requires `capabilities.workflows` to contain `export-project`; when absent the app is too old.

The app writes the rendered video into its own project storage; the CLI delivers it to `--output`. Because the app is sandboxed, never expect VideoHero itself to write to an arbitrary user path.

When `capabilities.presentation.persistsProject` is `true`, `presentation render` also creates an editable VideoHero project automatically. The project is created after preflight and is visible in VideoHero while generation is running; successful projects retain their PPTX/PDF, slide images, narration audio, previews, and an internal exported video in VideoHero's managed project storage. No `--save-project` parameter exists or is needed. A failed or cancelled import may be removed using the same cleanup semantics as a failed UI import.

The CLI does not provide standalone text-to-speech or audio-file generation. Presentation narration remains internal to the editable project and video-export workflow.

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

Terminal states are `succeeded`, `needs_review`, `failed`, and `cancelled`. Non-terminal states are expected to include `submitted`, `queued`, `preflighting`, `running`, `finalizing`, and `cancelling`.

`jobs wait --format ndjson` emits one complete JSON object whenever the observed status changes. Each line can include `stage`, `progress`, `message`, and the optional presentation `estimate`. Parse lines incrementally and surface meaningful changes rather than waiting for EOF. Text mode also streams human-readable updates; `--format json` intentionally emits only one final JSON document and is not a live-progress format.

`needs_review` means VideoHero finished narration but at least one page failed the automatic quality gate in a way that requires a human to listen and confirm. The status carries `reviewItems` (`page`, `reason`, `audioPath`) and `nextAction`. No video artifact is produced in this state. The CLI exits with code 5; do not treat it as a failure or retry it. The project remains editable in VideoHero; after the user confirms every listed page, run `videohero presentation export --project <projectId>` to finish the export without regenerating narration.

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
| `project_settings_conflict` / `project_conflict` | Re-read the project and reconcile; never overwrite with a stale request. |
| `script_conflict` / `image_conflict` | Re-read affected pages and preserve concurrent user edits. |
| `image_aspect_ratio_mismatch` | Generate or crop an image to the advertised project aspect ratio. |
| `project_requires_render` | Run `presentation render-project`; do not use export as a quality-check bypass. |
| `restart_interrupted` | Query artifacts and caches, then offer a retry with the same request and idempotency key. |

For uncertain submission outcomes, query by job id or reuse the same `--idempotency-key`. Never create repeated expensive jobs merely because the waiting process disconnected.
