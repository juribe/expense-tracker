#!/usr/bin/env python3
"""Local Speech-to-Text with faster-whisper.

Invoked by SpeechToText::Whisper. Rails knows nothing about this file beyond
its stable CLI contract:

    python script/whisper_transcribe.py [--model small] [--device cpu]
        [--compute-type int8] [--language es] [--beam-size 5] <audio_path>

Prints a single JSON object on success:

    {"ok": true, "text": "Este es un ejemplo.", "language": "es",
     "language_probability": 0.98, "duration": 5.2}

On failure prints {"ok": false, "error": "..."} and exits 1.
"""

import argparse
import json
import sys

DEFAULT_MODEL = "small"
DEFAULT_DEVICE = "cpu"
DEFAULT_COMPUTE_TYPE = "int8"
DEFAULT_BEAM_SIZE = 5


def parse_args():
    parser = argparse.ArgumentParser(description="Transcribe audio with faster-whisper")
    parser.add_argument("audio", help="Path to the (preprocessed) audio file")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--device", default=DEFAULT_DEVICE)
    parser.add_argument("--compute-type", default=DEFAULT_COMPUTE_TYPE)
    parser.add_argument("--language", default=None,
                        help="Force a language code (e.g. es); omit to auto-detect")
    parser.add_argument("--beam-size", type=int, default=DEFAULT_BEAM_SIZE)
    return parser.parse_args()


def fail(message):
    print(json.dumps({"ok": False, "error": message}))
    sys.exit(1)


def main():
    args = parse_args()

    try:
        from faster_whisper import WhisperModel
    except ImportError:
        fail("faster-whisper is not installed (see docs/speech_to_text.md).")

    try:
        model = WhisperModel(args.model, device=args.device, compute_type=args.compute_type)
        options = {
            "beam_size": args.beam_size,
            "vad_filter": False,
            "condition_on_previous_text": False,
        }
        if args.language:
            options["language"] = args.language
        segments, info = model.transcribe(args.audio, **options)

        # segments is a lazy generator: consume it fully to get all the text.
        texts = [segment.text.strip() for segment in segments]
        print(json.dumps({
            "ok": True,
            "text": "".join(texts).strip(),
            "language": info.language,
            "language_probability": getattr(info, "language_probability", None),
            "duration": getattr(info, "duration", None),
        }))
    except Exception as exc:  # noqa: BLE001 - the CLI boundary, not Rails
        fail(f"{type(exc).__name__}: {exc}"[:300])


if __name__ == "__main__":
    main()
