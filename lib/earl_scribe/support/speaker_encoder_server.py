#!/usr/bin/env python3
"""Persistent speaker encoder server.

Loads VoiceEncoder once, then loops reading JSON requests from stdin.

Protocol:
  --> {"cmd": "encode", "id": "1", "wav_path": "/tmp/foo.wav"}
  <-- {"id": "1", "embedding": [0.1, 0.2, ...]}
  --> {"cmd": "shutdown"}
"""

import json
import sys
from pathlib import Path

from resemblyzer import VoiceEncoder, preprocess_wav


def main():
    # VoiceEncoder prints "Loaded encoder..." to stdout on init; redirect to stderr
    _real_stdout = sys.stdout
    sys.stdout = sys.stderr
    encoder = VoiceEncoder()
    sys.stdout = _real_stdout

    # Signal readiness
    _real_stdout.write(json.dumps({"status": "ready"}) + "\n")
    _real_stdout.flush()

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            request = json.loads(line)
        except json.JSONDecodeError as e:
            _real_stdout.write(json.dumps({"error": str(e)}) + "\n")
            _real_stdout.flush()
            continue

        cmd = request.get("cmd")
        req_id = request.get("id")

        if cmd == "shutdown":
            break

        if cmd == "encode":
            handle_encode(request, req_id, encoder, _real_stdout)
        else:
            _real_stdout.write(json.dumps({"id": req_id, "error": f"unknown cmd: {cmd}"}) + "\n")
            _real_stdout.flush()


def handle_encode(request, req_id, encoder, out):
    wav_path = Path(request["wav_path"])
    if not wav_path.exists():
        out.write(json.dumps({"id": req_id, "error": f"file not found: {wav_path}"}) + "\n")
        out.flush()
        return

    try:
        wav = preprocess_wav(wav_path)
        embedding = encoder.embed_utterance(wav)
        out.write(json.dumps({"id": req_id, "embedding": embedding.tolist()}) + "\n")
        out.flush()
    except Exception as e:
        out.write(json.dumps({"id": req_id, "error": str(e)}) + "\n")
        out.flush()


if __name__ == "__main__":
    main()
