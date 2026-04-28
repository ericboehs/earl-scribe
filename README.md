# earl-scribe

Meeting transcription CLI. Captures system audio and your microphone, streams locally to [FluidAudio](https://github.com/FluidInference/FluidAudio)'s Parakeet EOU 120M model on the Apple Neural Engine for real-time transcription, identifies speakers via [resemblyzer](https://github.com/resemble-ai/Resemblyzer), and rolls out a live meeting summary via local Qwen + [llama.cpp](https://github.com/ggerganov/llama.cpp). Falls back to [Deepgram Nova-3](https://deepgram.com/) with `--cloud`.

## How It Works

The default pipeline on macOS 14.2+:

1. **System audio** (everyone else in the meeting) is captured via [AudioTee](https://github.com/makeusabrew/audiotee), a tiny Swift CLI that wraps Apple's Core Audio Taps API — no kernel extensions or virtual audio drivers (Loopback, BlackHole) required.
2. **Your microphone** is captured via `sox -t coreaudio <device>`, defaulting to whatever is set in System Settings → Sound → Input.
3. Both streams are mixed into mono and piped to the Swift `earl-scribe-asr` shim, which runs FluidAudio's streaming Parakeet EOU model on the Apple Neural Engine and emits JSONL transcript events. Real-time factor is ~17× on Apple Silicon at 320 ms chunks.
4. On each EOU (end-of-utterance) the corresponding PCM slice is fed to resemblyzer for speaker identification.
5. With `--summary`, a background timer re-summarizes the running transcript with a local Qwen GGUF (via `llama-cli`) every few minutes (or on `SIGUSR1`), overwriting `<session>-summary.md` next to the transcript.

Cloud Deepgram Nova-3 streaming remains available behind `--cloud`. Legacy single-device capture via `--device "Loopback Meeting"` is still supported as an escape hatch.

**Speaker identification** is an optional layer: enroll speakers from audio samples and earl-scribe attaches real names to the model's anonymous `Speaker N` labels using voiceprint cosine similarity.

## Requirements

- **macOS 14.2+** + Apple Silicon (for AudioTee's Core Audio Taps API and FluidAudio on the Neural Engine)
- **Ruby** >= 3.0
- **Swift toolchain** (one-time, for building AudioTee + the `earl-scribe-asr` shim — ships with Xcode or Command Line Tools)
- **SoX** — `brew install sox`

### Optional

- **FFmpeg** (only needed if using `--record` to save M4A alongside transcription) — `brew install ffmpeg`
- **llama.cpp + Qwen GGUF** (for the rolling meeting summarizer) — `brew install llama.cpp`, then `bin/build-qwen`
- **Deepgram API key** (only needed for `--cloud`) — [Get one free](https://console.deepgram.com/signup)
- **Python 3** + `resemblyzer` (for speaker identification)

## Installation

```bash
gem install earl-scribe
```

Or from a Gemfile:

```ruby
gem "earl-scribe"
```

### Build the external pieces

```bash
bin/build-audiotee   # clones + builds the audiotee CLI
bin/build-asr        # builds the Swift earl-scribe-asr shim (depends on FluidAudio)
bin/build-qwen       # verifies llama-cli is on PATH + downloads a Qwen GGUF model
```

Each script prints the env var you should export (e.g. `EARL_SCRIBE_AUDIOTEE_PATH`,
`EARL_SCRIBE_ASR_BIN`, `EARL_SCRIBE_QWEN_MODEL`) or you can put the binaries on
your PATH and skip the env vars.

When you first run earl-scribe, macOS will prompt your terminal for **Microphone** and **System Audio Recording** permissions. Grant both.

## Configuration

```bash
# Optional: external binary locations (default to PATH lookup)
export EARL_SCRIBE_AUDIOTEE_PATH="/path/to/audiotee"
export EARL_SCRIBE_ASR_BIN="/path/to/earl-scribe-asr"
export EARL_SCRIBE_LLAMA_BIN="llama-cli"
export EARL_SCRIBE_QWEN_MODEL="$HOME/.config/earl-scribe/models/qwen2.5-3b-instruct-q4_k_m.gguf"

# Optional: streaming chunk size in ms (160, 320, or 1280; default 320)
export EARL_SCRIBE_ASR_CHUNK_MS="320"

# Optional: rolling summary cadence (default 180s; takes effect with --summary)
export EARL_SCRIBE_SUMMARY_INTERVAL_SEC="180"
export EARL_SCRIBE_SUMMARIZE="1"   # opt in via env instead of --summary

# Optional: mic device name for sox (default: "default" — macOS system default input)
export AUDIO_MIC="Streamer X Main"

# Optional: escape hatch — when set, single-device capture replaces dual capture
export AUDIO_DEVICE="Loopback Meeting"

# Optional: sample rate (default 48000)
export AUDIO_SAMPLE_RATE="48000"

# Required only for --cloud
export DEEPGRAM_API_KEY="your-api-key"
```

## Usage

### Transcribe

```bash
# Default: system audio + default mic, mixed to mono, local Parakeet streaming
earl-scribe transcribe

# Cloud: stream to Deepgram Nova-3 instead
earl-scribe transcribe --cloud

# Cloud + stereo: L=system, R=mic, per-channel diarization (use headphones to avoid echo)
earl-scribe transcribe --cloud --stereo

# No mic — system audio only (useful when only transcribing remote participants)
earl-scribe transcribe --no-mic

# Override the mic device
earl-scribe transcribe --mic "Streamer X Main"

# Legacy single-device capture (Loopback Meeting, USB mixers, etc.)
earl-scribe transcribe --device "Loopback Meeting"

# Record audio to M4A alongside transcription
earl-scribe transcribe --record

# Set a meeting title (otherwise auto-detected from calendar)
earl-scribe transcribe --title "Team Standup"

# Enable the rolling Qwen summarizer (writes <session>-summary.md alongside the transcript)
earl-scribe transcribe --summary

# Override summary cadence (default 180s)
earl-scribe transcribe --summary --summary-interval-sec 90

# Force an immediate summary regen mid-meeting
kill -USR1 $(pgrep -f earl-scribe)
```

### Mono mix vs. cloud stereo

The local Parakeet engine always operates on a mono mix. Deepgram (`--cloud`) supports a stereo mode where diarization runs per channel independently:

- **Cloud mono mix**: Deepgram's diarization tends to collapse everyone into `Speaker 0` because mic and system audio overlap in the same bitspace.
- **Cloud `--stereo`**: Per-channel diarization, giving `Ch0 Speaker 0` (system) vs `Ch1 Speaker 0` (you). Use this when wearing headphones. On speakers, mic echo duplicates remote audio onto the mic channel.

Speaker identification (resemblyzer) runs on the mono PCM regardless and resolves `Speaker N` labels to enrolled names.

### List Audio Devices

```bash
earl-scribe devices
```

### Speaker Identification

Optional. Requires Python 3 with resemblyzer (`pip install resemblyzer`).

```bash
# Enroll a speaker from audio samples
earl-scribe speakers enroll "Alice" meeting1.wav meeting2.wav

# List enrolled speakers
earl-scribe speakers list

# Identify who's speaking in an audio file
earl-scribe speakers identify unknown.wav

# Show similarity scores against all enrolled speakers
earl-scribe speakers test unknown.wav

# Remove a speaker
earl-scribe speakers delete "Alice"
```

Voiceprints are stored as JSON files in `~/.config/earl-scribe/speakers/`.

## Development

```bash
git clone https://github.com/ericboehs/earl-scribe.git
cd earl-scribe
bundle install
bin/build-audiotee   # one-time
bin/build-asr        # one-time (FluidAudio Swift shim)
bin/build-qwen       # one-time (downloads Qwen GGUF for the summarizer)

# Run full CI pipeline (RuboCop, Reek, Bundler audit, Semgrep, Minitest, Coverage)
bin/ci

# Tests only
bundle exec rake test

# Auto-fix style
bundle exec rubocop -A
```

Coverage floor: 95% line + branch.

## License

[MIT](LICENSE)
