#!/usr/bin/env python3
"""Generate a speaker embedding from a WAV file using resemblyzer.

Usage: python3 speaker_encoder.py <wav_path>
Output: JSON array of 256 floats to stdout
"""

import json
import sys
from pathlib import Path

from resemblyzer import VoiceEncoder, preprocess_wav


def main():
    if len(sys.argv) != 2:
        print("Usage: speaker_encoder.py <wav_path>", file=sys.stderr)
        sys.exit(1)

    wav_path = Path(sys.argv[1])
    if not wav_path.exists():
        print(f"Error: file not found: {wav_path}", file=sys.stderr)
        sys.exit(1)

    encoder = VoiceEncoder()
    wav = preprocess_wav(wav_path)
    embedding = encoder.embed_utterance(wav)
    print(json.dumps(embedding.tolist()))


if __name__ == "__main__":
    main()
