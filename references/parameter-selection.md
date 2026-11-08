# Choosing the engine and the voice

`--engine` and `--voice` are **user decisions**, not agent defaults. The CLI requires
`--engine` and treats `--voice` as optional (falling back to the engine's first voice); neither
is the user's choice, so an agent must not rely on CLI behavior. This reference is mandatory for
`tts generate` and `presentation render`. `presentation export` reuses the project's existing
engine and voice, so it needs no new choice.

## The two required choices

| Parameter | Authoritative source | Scope |
|---|---|---|
| `--engine` | `capabilities.ttsEngineIDs` + `capabilities.engineReadiness` | one engine per job |
| `--voice` | `videohero voices list --engine <engine-id> --format json` | voice ids are engine-scoped |

Never infer either value from the CLI default, a previous job, the user's history, a voice
title, or the fact that an earlier generation used it.

## What the user sees

### 1. Every engine

Show one table with **all** engine ids returned by `capabilities.ttsEngineIDs`. Include
unavailable engines: the user needs the full picture, and an unavailable engine is a reason to
ask for authorization, not a reason to hide it.

| 序号 | 引擎 | 引擎 ID | 状态 | 音色数 |
|---|---|---|---|---|
| 1 | Qwen3 TTS | qwen3PresetVoice | 就绪 | 19 |
| 2 | CosyVoice | cosyVoice | 就绪 | 19 |
| 3 | MOSS-TTS Nano | mossTTSNano | 就绪 | 28 |
| 4 | KokoroTTS | kokoroTTS | 就绪 | 45 |
| 5 | Ming-3.0-TTS | mingTTS | 缺少模型 | 32 |

- Status comes from `engineReadiness`: `modelReady`, `helperReady`, and `issues`. A non-ready
  engine must be described as such, with the advertised issue text.
- Voice count comes from the number of `ttsVoices` entries with that `engineID`. If
  `ttsVoices` is absent, say the count is unknown instead of inventing one.
- Do **not** mark a “default”, “recommended”, or “best” engine, and do not pre-select row 1.
  Offer a recommendation only when the user asks for one, and say what it is based on.
- The display name is presentation only. The id remains the identifier:

| engine id | Display name (presentation only) |
|---|---|
| `qwen3PresetVoice` | Qwen3 TTS |
| `cosyVoice` | CosyVoice |
| `mossTTSNano` | MOSS-TTS Nano |
| `kokoroTTS` | KokoroTTS |
| `mingTTS` | Ming-3.0-TTS |

  An id missing from this table is shown as-is. Never add an engine that `capabilities` did not
  advertise, even if it appears in this table.

### 2. Every voice of the chosen engine

After the user picks an engine, run `videohero voices list --engine <engine-id> --format json`
and list **every** returned entry:

| 序号 | 音色 | 音色 ID | 语言 |
|---|---|---|---|
| 1 | 我的声音 | videohero.personal-voice.v1 | zh |
| 2 | 温柔邻家女声 | F0_温柔邻家女声 | zh |
| 3 | 知性女主播 | F1_知性女主播 | zh |
| … | … | … | … |

- Personal voice appears only when the command returns it. Never add it by assumption.
- Do not truncate, sample, group away, reorder into a “shortlist”, or pre-select an entry.
  Long lists are acceptable; completeness is the requirement.
- The `title` is for the user; the `id` is for the command.

## Interaction rules

1. **Both missing.** Show engines, ask for one; after the answer, show that engine's voices and
   ask for one. Two turns are expected because the voice list depends on the engine.
2. **Only the engine is missing.** Ask for the engine, showing all engines. Do not ask for the
   voice again if the user already named it, but verify it belongs to the chosen engine.
3. **Only the voice is missing.** Show every voice of the already-chosen engine.
4. **Only a voice title was given.** Find every engine whose `voices list` contains that exact
   title (preset titles are shared across several engines). Show the voice with an engine column,
   and let the user confirm the engine.
5. **Ambiguous description** (“a female voice”, “the news one”). Show every matching voice with
   its engine, and ask. Do not pick the first match.
6. **The user changes engine after choosing a voice.** Re-show the new engine's full voice list
   and confirm a voice again; do not carry the old voice over silently, even if the title exists.
7. **Delegation** (“随便”, “you decide”, “用默认的”). Treat this as permission to propose, not to
   decide: propose one concrete engine + voice pair with a one-line reason and wait. Proceed
   without confirmation only when the user explicitly said to start without further questions;
   even then, state the final pair in the submission summary and how to change it.
8. **The host cannot ask the user** (batch/one-shot execution). Do not generate. Return the full
   engine table, explain that the voice list needs the engine first, and provide the exact
   commands for the next turn (`voices list --engine <id>`, then the `tts generate` /
   `presentation render` template with `--engine` and `--voice` placeholders).
9. **The user names an engine by display name.** Map it to an id through the display-name table
   only when exactly one advertised engine matches; otherwise show the engine table and ask.
10. **A job is retried or re-exported.** Keep the engine and voice already chosen for that
    request. Export takes no engine/voice; a retry that changes either one needs a new explicit
    choice.

## After the choice

```bash
videohero voices list --engine <engine-id> --format json   # confirm the voice id is present
videohero doctor --workflow <tts|presentation-to-video> --engine <engine-id> --voice <voice-id> --format json
```

For presentation, add `--subtitles burn` (and any other value you intend to submit) to `doctor`,
so preflight checks the same settings the job will use.

Then submit with both flags, and summarize for the user:

> 引擎：Qwen3 TTS（qwen3PresetVoice）
> 音色：知性女主播（F1_知性女主播）
> 其余参数使用默认：脚本来源 notes-or-body、比例 source、字幕 burn、语言 auto

An engine or voice must not change during generation. A new engine or voice means a new
confirmed choice. `presentation export` does not regenerate narration and takes no engine/voice.

## Failure handling

| Situation | Behavior |
|---|---|
| Chosen engine is not ready | Report the `issues` text; offer another engine or an authorized model download/repair. Never substitute an engine. |
| `voice_not_found` | Refresh the full `voices list` for that engine, then ask again. Keep the engine. |
| `authorization_required` (personal voice) | Ask the user to finish the “我的声音” flow in VideoHero; keep the engine and the intent. Do not switch engines. |
| `protocol_incompatible` / capabilities cannot be decoded | Stop; the CLI and App versions do not match. Ask for a skill/CLI update. Do not guess engines or voices. |
| `capabilities` has no `ttsVoices` | Tell the user discovery is incomplete and that VideoHero must be running with agent control enabled; do not invent a voice list. |

## Discovery payload

`capabilities --format json` exposes the full set; `voices list --format json` exposes the
voice array. A representative shape:

```json
{
  "ttsEngineIDs": ["qwen3PresetVoice", "cosyVoice", "mossTTSNano", "kokoroTTS", "mingTTS"],
  "engineReadiness": [
    { "engineID": "qwen3PresetVoice", "modelReady": true, "helperReady": true, "issues": [] }
  ],
  "ttsVoices": [
    { "id": "F0_温柔邻家女声", "engineID": "qwen3PresetVoice", "title": "温柔邻家女声", "languageCode": "zh" }
  ]
}
```

Use the installed result as authority. Fields can be absent on older snapshots; treat absence as
unknown, never as “use the default”.
