# earl-scribe

Meeting transcription CLI. Captures audio via FFmpeg and streams to [Deepgram Nova-3](https://deepgram.com/) for real-time transcription with speaker diarization, or transcribes locally via [whisper.cpp](https://github.com/ggerganov/whisper.cpp).

Optionally identifies speakers by name using voiceprint matching via [resemblyzer](https://github.com/resemble-ai/Resemblyzer) (Python).

## How It Works

**Deepgram mode** (default) captures audio from your Mac's microphone or a virtual audio device, streams raw PCM over a WebSocket to Deepgram's API, and prints transcribed text with speaker labels in real-time.

In **stereo mode** (default), the left channel is the meeting audio (with diarization — Deepgram labels speakers as "Speaker 0", "Speaker 1", etc.) and the right channel is your microphone. In **mono mode**, all audio is mixed and diarized together.

**Speaker identification** is an optional layer on top: enroll speakers by providing audio samples, and earl-scribe can match Deepgram's anonymous speaker labels to real names using voiceprint cosine similarity.

**Local mode** uses whisper.cpp for offline transcription (not yet fully implemented in the streaming pipeline).

## Requirements

- **Ruby** >= 2.6
- **FFmpeg** (for audio capture) — `brew install ffmpeg`
- **Deepgram API key** (for streaming mode) — [Get one free](https://console.deepgram.com/signup)

### Optional

- **whisper.cpp** + model files (for local transcription)
- **Python 3** + `resemblyzer` (for speaker identification only)

## Installation

```bash
gem install earl-scribe
```

Or add to your Gemfile:

```ruby
gem "earl-scribe"
```

## Configuration

Set these environment variables:

```bash
# Required for Deepgram streaming
export DEEPGRAM_API_KEY="your-api-key"

# Optional: default audio device (name or index)
export AUDIO_DEVICE="Meeting"

# Optional: local whisper.cpp
export WHISPER_CPP_PATH="/path/to/whisper-cpp"
export WHISPER_MODELS_DIR="/path/to/models"
export WHISPER_MODEL="base.en"  # default
```

## Usage

### Transcribe

```bash
# Stream to Deepgram (stereo: L=meeting, R=mic)
earl-scribe transcribe

# Mono mode (single mixed channel)
earl-scribe transcribe --mono

# Use a specific audio device
earl-scribe transcribe --device "Meeting"
earl-scribe transcribe --device 2

# Local whisper.cpp (experimental)
earl-scribe transcribe --local
```

### List Audio Devices

```bash
earl-scribe devices
```

### Speaker Identification

Speaker identification requires Python 3 with resemblyzer (`pip install resemblyzer`). It is **not required** for transcription — Deepgram handles diarization natively.

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

Speaker voiceprints are stored as JSON files in `~/.config/earl-scribe/speakers/`.

## Development

```bash
git clone https://github.com/ericboehs/earl-scribe.git
cd earl-scribe
bundle install

# Run the full CI pipeline
bin/ci

# Run tests only
bundle exec rake test

# Auto-fix style issues
bundle exec rubocop -A
```

The CI pipeline runs: RuboCop, Reek, Bundler audit, Semgrep, Minitest (153 tests), and SimpleCov (95% line + branch coverage required).

## License

[MIT](LICENSE)
