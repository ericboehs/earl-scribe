# CLAUDE.md

## Project Overview

**earl-scribe** is a Ruby gem CLI for meeting transcription. It captures audio via FFmpeg, streams to Deepgram Nova-3 for real-time transcription with speaker diarization, or transcribes locally via whisper.cpp. Includes speaker identification via voiceprint matching (Python/resemblyzer).

## Architecture

```
lib/
  earl_scribe.rb                         # Module root, config_root, logger, Error
  earl_scribe/
    version.rb                           # VERSION constant
    config.rb                            # ENV-based config (DEEPGRAM_API_KEY, etc.)
    cli.rb                               # Dispatcher: transcribe, speakers, devices
    cli/
      transcribe.rb                      # Deepgram streaming / local whisper.cpp
      speakers.rb                        # enroll/list/delete/identify/test
      devices.rb                         # List avfoundation audio devices
    audio/
      device.rb                          # Resolve device name -> index via ffmpeg
      capture.rb                         # FFmpeg audio capture (streaming + chunked)
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
earl-scribe transcribe                    # Deepgram streaming (default)
earl-scribe transcribe --local            # Local whisper.cpp
earl-scribe transcribe --device "Name"    # Specific audio device
earl-scribe transcribe --mono             # Mono mode
earl-scribe transcribe --no-identify      # Skip speaker identification

earl-scribe speakers enroll "Name" file.wav [file2.wav ...]
earl-scribe speakers list
earl-scribe speakers delete "Name"
earl-scribe speakers identify file.wav
earl-scribe speakers test file.wav

earl-scribe devices                       # List audio devices
```

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
- **External**: ffmpeg, whisper.cpp (optional), Python 3 + resemblyzer (optional)
