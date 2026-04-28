# WhisperKit (Argmax) POC — 2026-04-27

Goal: evaluate whether to replace Parakeet (FluidAudio) with WhisperKit + SpeakerKit.
Trigger: Parakeet 0.6B batch drops first ~22s of audio (FluidAudio #212).

## Setup

```
brew install whisperkit-cli   # already installed (0.4.x)
```

Models tested:
- `large-v3-v20240930` (full, ~1.6GB)
- `large-v3-v20240930_turbo` (~600MB, ANE-optimized)

Test fixture: `test/fixtures/benchmark/eert-retro-60s.wav`
(60s mono 16k, 2 speakers — Allison + Jason. Reference in `eert-retro-60s-reference.md`.)

## Results

### Performance — Apple M-series (post-warm-cache)

| Model            | Pipeline | Realtime  | Cold-start model load |
|------------------|----------|-----------|------------------------|
| large-v3 full    | 4.48s    | **13.4×** | ~18s ASR + ~14s diar   |
| large-v3 turbo   | 3.42s    | **17.6×** | ~1.2s warm             |

Both fast enough for live streaming after first session warms cache.

### Transcription accuracy (vs reference)

Identical between full and turbo. Errors on the 60s clip:
- "Brooks" instead of "Brooke's" (possessive missed)
- "you all" instead of "y'all" (style; both correct)
- **"I didn't write that"** instead of **"I CAN write that"** (substantive error)
- Inserts a few "like" fillers Whisper hears in audio

Compared to current Parakeet 0.6B batch:
- **Parakeet drops the entire first 22 seconds** (FluidAudio #212 chunk-boundary bug)
- WhisperKit captures all 60 seconds
- Both make the "I CAN/didn't" error
- Both correctly capture mid-meeting content

### Diarization (built into `whisperkit-cli transcribe --diarization`)

Reference truth: Allison · Jason · Allison · Allison · Jason · Jason

WhisperKit auto:
- ✓ B (Allison): 0:00-08.9
- ✓ A (Jason): 12.8-30.7
- ✓ B (Allison): 29.4-47.2
- ✗ C (mixed): 51.4-59.98 — merges Allison's "I can write…" with Jason's "Ah, thank you. Okay, let's start at the top." into one anonymous speaker

WhisperKit `--diarization-num-speakers 2`:
- Same A/B labels for Allison's two segments (correct re-identification)
- Still merges trailing Jason into Allison's last segment (boundary miss)

Verdict: **3.5/4 turns correct.** Diarization quality comparable to Sortformer in our streaming path, with the same kind of edge-case turn-boundary miss. Speaker labels are A/B/C — would need a separate enrollment step (current resemblyzer) to map back to names, OR train SpeakerKit voiceprints.

## Bottom line

WhisperKit large-v3-turbo on Apple Silicon:
- ✅ **17.6× realtime** for batch + diarization in one shot
- ✅ Fixes the Parakeet first-chunk drop
- ✅ Built-in diarization removes the Sortformer dependency
- ❌ Speaker labels are anonymous — still need name mapping (resemblyzer enrollments stay relevant)
- ➡ Comparable WER to Parakeet on this clip

## Recommendation

Worth integrating. Path forward:

1. Replace `--batch` rerun with `whisperkit-cli transcribe --diarization` shellout (keeps current architecture, swaps the batch backend)
2. Keep Parakeet 120M streaming for live (still fastest at 17×)
3. Reuse resemblyzer to map WhisperKit's A/B/C labels to enrolled names
4. Eventually evaluate WhisperKit's `--stream` mode to replace live path too (latency 0.46s reported in Argmax's paper)

Out: keep Parakeet's `--batch` mode pinned to streaming until FluidAudio fixes #212.

## Raw outputs

- `/tmp/argmax-poc/eert-retro-60s.{json,srt}` — large-v3 full
- `/tmp/argmax-poc-turbo/eert-retro-60s.{json,srt}` — turbo
