# CLAUDE.md

## Project Overview

**earl-scribe** is a Ruby gem CLI for meeting transcription. Default capture pipeline on macOS 14.2+ combines system audio (via AudioTee / Core Audio Taps) with a hardware mic (via sox/CoreAudio), mixed to mono and streamed in real time to a local FluidAudio Parakeet EOU 120M model via the Swift `earl-scribe-asr` shim. Speaker identification continues via the existing resemblyzer pipeline. Pass `--summary` to enable a rolling local Qwen summarizer (llama.cpp) that overwrites `<session>-summary.md` next to the transcript. Cloud Deepgram Nova-3 remains available behind `--cloud`. Legacy single-device capture via `--device` is preserved.

## Architecture

```
lib/
  earl_scribe.rb                         # Module root, config_root, logger, Error
  earl_scribe/
    version.rb                           # VERSION constant
    config.rb                            # ENV-based config (DEEPGRAM_API_KEY, EARL_SCRIBE_ASR_BIN, etc.)
    cli.rb                               # Dispatcher: transcribe, speakers, devices
    cli/
      transcribe.rb                      # Local-stream + cloud orchestration
      transcribe_mode.rb                 # Channel count + banner labels per capture mode
      transcribe_session.rb              # Builds capture + writers; picks DualCapture / AudioTee / Capture
      transcribe_summarizer.rb           # Wires Summarizer::Scheduler + Qwen into a session
      speakers.rb                        # enroll/list/delete/identify/test
      devices.rb                         # List avfoundation audio devices
    audio/
      device.rb                          # Resolve device name -> index via ffmpeg
      capture.rb                         # Single-device capture (sox/CoreAudio or ffmpeg/AVFoundation)
      audiotee.rb                        # System-audio-only capture via audiotee CLI
      dual_capture.rb                    # AudioTee + sox, mono mix or stereo interleave (default)
    transcription/
      local_stream.rb                    # Pipes PCM to earl-scribe-asr Swift shim, parses JSONL events
      local_stream_event_parser.rb       # JSONL → Result-shaped hashes (handles eou + final tail)
      deepgram.rb                        # WebSocket client + WebsocketFactory + MessageHandler
      result.rb                          # Transcript segment Struct
      result_parser.rb                   # Deepgram JSON response parser
      word_grouper.rb                    # Groups words by speaker into segments
    summarizer/
      qwen.rb                            # llama-cli + Qwen GGUF subprocess wrapper
      scheduler.rb                       # Rolling re-summary timer + SIGUSR1 trap
    speaker/
      store.rb                           # JSON persistence (~/.config/earl-scribe/speakers/)
      encoder.rb                         # Python resemblyzer helper via Open3
      identifier.rb                      # Cosine similarity matching + VectorMath
    support/
      speaker_encoder.py                 # Python helper for voice embeddings
swift/
  earl-scribe-asr/                       # SwiftPM shim wrapping FluidAudio StreamingEouAsrManager
exe/
  earl-scribe                            # CLI entry point
```

## CLI Usage

```bash
earl-scribe transcribe                    # Default: local Parakeet streaming, dual capture mono mix
earl-scribe transcribe --no-mic           # Local stream, AudioTee system-audio only
earl-scribe transcribe --mic "Name"       # Override mic device (default: "default")
earl-scribe transcribe --device "Name"    # Escape hatch: single-device capture
earl-scribe transcribe --no-identify      # Skip speaker identification
earl-scribe transcribe --summary          # Enable rolling Qwen summarizer (off by default)
earl-scribe transcribe --summary --summary-interval-sec 120  # Override summary cadence (default 180s)
earl-scribe transcribe --cloud            # Stream to Deepgram Nova-3 instead
earl-scribe transcribe --cloud --stereo   # Cloud, L=system R=mic interleaved
kill -USR1 <pid>                          # Trigger an immediate summary regen

earl-scribe speakers enroll "Name" file.wav [file2.wav ...]
earl-scribe speakers list
earl-scribe speakers delete "Name"
earl-scribe speakers identify file.wav
earl-scribe speakers test file.wav

earl-scribe devices                       # List audio devices
```

## Build external pieces

```
bin/build-audiotee       # Clones + builds the audiotee CLI; prints export path
bin/build-asr            # Builds the Swift earl-scribe-asr shim; prints export path
bin/build-qwen           # Verifies llama-cli + downloads the Qwen GGUF model
```

Set the corresponding env vars (`EARL_SCRIBE_AUDIOTEE_PATH`, `EARL_SCRIBE_ASR_BIN`,
`EARL_SCRIBE_QWEN_MODEL`) or put the binaries on PATH.

## Development Commands

- `bin/ci` -- Full CI pipeline (RuboCop, Reek, Bundler audit, Semgrep, Minitest, Coverage)
- `bundle exec rake test` -- Run test suite
- `bundle exec rubocop -A` -- Auto-fix style violations
- `bundle exec reek` -- Code quality check
- `bin/coverage` -- Check 95% line + branch coverage

## Code Quality

This project uses vanilla RuboCop, Reek, and Semgrep with minimal configuration. Do not:

- Add `# rubocop:disable` inline comments
- Add `# :reek:` inline annotations
- Use `# nosemgrep` unless the finding is a verified false positive (e.g., `Open3` with array-form arguments)

## Testing

- Minitest with DeclarativeTests DSL: `test "name" { }`
- SimpleCov at 95% line + branch coverage
- Use `Object#stub(:method, value) { }` for auto-restoring stubs (preferred)
- `stub_singleton` in test_helper.rb is available but does NOT auto-restore
- Fixtures in `test/fixtures/`

## Dependencies

- **Runtime**: `websocket-client-simple ~> 0.9`
- **External**: audiotee (built via `bin/build-audiotee`), the Swift `earl-scribe-asr` shim (built via `bin/build-asr`, depends on FluidAudio + Apple Silicon), sox, ffmpeg (for `--record` only), llama.cpp + a Qwen GGUF (for the summarizer; optional), Python 3 + resemblyzer (for speaker ID; optional)
