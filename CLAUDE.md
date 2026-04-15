# CLAUDE.md

## Project Overview

**earl-scribe** is a Ruby gem CLI for meeting transcription. Default capture pipeline on macOS 14.2+ combines system audio (via AudioTee / Core Audio Taps) with a hardware mic (via sox/CoreAudio), mixed to mono and streamed to Deepgram Nova-3 for real-time transcription with diarization. Legacy single-device capture via `--device` is preserved. Local whisper.cpp chunked path still exists for offline transcription.

## Architecture

```
lib/
  earl_scribe.rb                         # Module root, config_root, logger, Error
  earl_scribe/
    version.rb                           # VERSION constant
    config.rb                            # ENV-based config (DEEPGRAM_API_KEY, etc.)
    cli.rb                               # Dispatcher: transcribe, speakers, devices
    cli/
      transcribe.rb                      # Deepgram streaming orchestration
      transcribe_mode.rb                 # Channel count + banner labels per capture mode
      transcribe_session.rb              # Builds capture + writers; picks DualCapture / AudioTee / Capture
      transcribe_local.rb                # Whisper.cpp chunked path
      speakers.rb                        # enroll/list/delete/identify/test
      devices.rb                         # List avfoundation audio devices
    audio/
      device.rb                          # Resolve device name -> index via ffmpeg
      capture.rb                         # Single-device capture (sox/CoreAudio or ffmpeg/AVFoundation)
      audiotee.rb                        # System-audio-only capture via audiotee CLI
      dual_capture.rb                    # AudioTee + sox, mono mix or stereo interleave (default)
    transcription/
      deepgram.rb                        # WebSocket client + WebsocketFactory + MessageHandler
      whisper.rb                         # whisper.cpp subprocess wrapper
      hallucination_filter.rb            # Regex filter for whisper false positives
      result.rb                          # Transcript segment Struct
      result_parser.rb                   # Deepgram JSON response parser
      word_grouper.rb                    # Groups words by speaker into segments
    speaker/
      store.rb                           # JSON persistence (~/.config/earl-scribe/speakers/)
      encoder.rb                         # Python resemblyzer helper via Open3
      identifier.rb                      # Cosine similarity matching + VectorMath
    support/
      speaker_encoder.py                 # Python helper for voice embeddings
exe/
  earl-scribe                            # CLI entry point
```

## CLI Usage

```bash
earl-scribe transcribe                    # Dual capture (AudioTee system + sox mic), mono mix
earl-scribe transcribe --stereo           # Dual capture, L=system R=mic interleaved
earl-scribe transcribe --no-mic           # AudioTee system-audio only
earl-scribe transcribe --mic "Name"       # Override mic device (default: "default")
earl-scribe transcribe --device "Name"    # Escape hatch: single-device capture
earl-scribe transcribe --local --device X # Local whisper.cpp (needs --device)
earl-scribe transcribe --no-identify      # Skip speaker identification

earl-scribe speakers enroll "Name" file.wav [file2.wav ...]
earl-scribe speakers list
earl-scribe speakers delete "Name"
earl-scribe speakers identify file.wav
earl-scribe speakers test file.wav

earl-scribe devices                       # List audio devices
```

## Build AudioTee

```
bin/build-audiotee       # Clones + builds into vendor/audiotee/, prints export path
```

Then `export EARL_SCRIBE_AUDIOTEE_PATH=...` or put the binary on PATH.

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
- **External**: audiotee (built via `bin/build-audiotee`), sox, ffmpeg (for `--record` only), whisper.cpp (optional), Python 3 + resemblyzer (optional)
