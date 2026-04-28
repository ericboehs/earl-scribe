# earl-scribe-whisperkit (spike)

Streaming WhisperKit shim — reads Float32 16k mono PCM from stdin, emits JSONL
events on stdout via `AudioStreamTranscriber`.

This is a spike (see `docs/argmax-poc.md`) proving WhisperKit can replace the
FluidAudio Parakeet shim for the live transcription path.

## Build

```
swift build -c release
```

## Run

```
ffmpeg -i input.wav -f f32le -ac 1 -ar 16000 - 2>/dev/null \
  | .build/release/earl-scribe-whisperkit \
      --model-path /path/to/openai_whisper-large-v3-v20240930
```

Emits one JSON line per state change:

```
{"type":"models_loaded"}
{"type":"start","started_at":"2026-04-28T13:06:58Z"}
{"type":"confirmed","start_sec":0.02,"end_sec":6.94,"text":"like kind of between a rock and a hard place..."}
{"type":"unconfirmed","start_sec":...,"end_sec":...,"text":"..."}
{"type":"partial","text":"current accumulating text"}
```

## Status

Spike-quality. Validated end-to-end on the 60s benchmark — captured Allison's
opening (which Parakeet drops) and got "I can write" correct (which the batch
CLI gets wrong). Next: integrate into Ruby's `Transcription::LocalStream`
behind a `--engine whisperkit` flag.
