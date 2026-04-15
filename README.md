# earl-scribe

Meeting transcription CLI. Captures system audio and your microphone, streams to [Deepgram Nova-3](https://deepgram.com/) for real-time transcription with speaker diarization, or transcribes locally via [whisper.cpp](https://github.com/ggerganov/whisper.cpp).

Optionally identifies speakers by name using voiceprint matching via [resemblyzer](https://github.com/resemble-ai/Resemblyzer) (Python).

## How It Works

The default pipeline on macOS 14.2+:

1. **System audio** (everyone else in the meeting) is captured via [AudioTee](https://github.com/makeusabrew/audiotee), a tiny Swift CLI that wraps Apple's Core Audio Taps API — no kernel extensions or virtual audio drivers (Loopback, BlackHole) required.
2. **Your microphone** is captured via `sox -t coreaudio <device>`, defaulting to whatever is set in System Settings → Sound → Input.
3. Both streams are mixed into mono (or interleaved to stereo with `--stereo`) and sent to Deepgram for real-time transcription with diarization.

Legacy single-device capture via `--device "Loopback Meeting"` (or any CoreAudio device) is still supported as an escape hatch.

**Speaker identification** is an optional layer: enroll speakers from audio samples and earl-scribe matches Deepgram's anonymous `Speaker N` labels to real names using voiceprint cosine similarity.

## Requirements

- **macOS 14.2+** (for AudioTee's Core Audio Taps API)
- **Ruby** >= 3.0
- **Swift toolchain** (one-time, for building AudioTee — ships with Xcode or Command Line Tools)
- **SoX** — `brew install sox`
- **Deepgram API key** — [Get one free](https://console.deepgram.com/signup)

### Optional

- **FFmpeg** (only needed if using `--record` to save M4A alongside transcription) — `brew install ffmpeg`
- **whisper.cpp** + model files (for `--local` offline transcription)
- **Python 3** + `resemblyzer` (for speaker identification)

## Installation

```bash
gem install earl-scribe
```

Or from a Gemfile:

```ruby
gem "earl-scribe"
```

### Build AudioTee

AudioTee is a separate binary that must be built once. From a checkout of earl-scribe:

```bash
bin/build-audiotee
```

This clones and builds [makeusabrew/audiotee](https://github.com/makeusabrew/audiotee) into `vendor/audiotee/` and prints the export command to put on PATH:

```bash
export EARL_SCRIBE_AUDIOTEE_PATH="/path/printed/by/script"
```

Alternatively, symlink the binary onto your `PATH` (e.g. `ln -s ... /usr/local/bin/audiotee`) and skip the env var.

When you first run earl-scribe, macOS will prompt your terminal for **Microphone** and **System Audio Recording** permissions. Grant both.

## Configuration

```bash
# Required for Deepgram streaming
export DEEPGRAM_API_KEY="your-api-key"

# Optional: audiotee binary location (default: "audiotee" on PATH)
export EARL_SCRIBE_AUDIOTEE_PATH="/path/to/audiotee"

# Optional: mic device name for sox (default: "default" — macOS system default input)
export AUDIO_MIC="Streamer X Main"

# Optional: escape hatch — when set, single-device capture replaces dual capture
export AUDIO_DEVICE="Loopback Meeting"

# Optional: sample rate (default 48000)
export AUDIO_SAMPLE_RATE="48000"

# Optional: whisper.cpp for --local mode
export WHISPER_CPP_PATH="/path/to/whisper-cpp"
export WHISPER_MODELS_DIR="/path/to/models"
export WHISPER_MODEL="large-v3"
```

## Usage

### Transcribe

```bash
# Default: system audio + default mic, mixed to mono
earl-scribe transcribe

# Stereo: L=system, R=mic, per-channel diarization (use headphones to avoid echo)
earl-scribe transcribe --stereo

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

# Local whisper.cpp (requires --device; whisper.cpp path operates on single-device chunks)
earl-scribe transcribe --local --device "Loopback Meeting"
```

### Speaker Diarization Tradeoff

- **Mono mix (default)**: Deepgram's diarization runs on a single mixed stream and often collapses everyone into `Speaker 0` because mic and system audio overlap in the same bitspace.
- **`--stereo`**: Deepgram runs diarization per channel independently, giving you `Ch0 Speaker 0` (system) vs `Ch1 Speaker 0` (you). Use this when wearing headphones. On speakers, mic echo duplicates remote audio onto the mic channel, causing duplicate transcripts.

If diarization quality matters and you use speakers, the cleanest solve is to use headphones with `--stereo`.

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
