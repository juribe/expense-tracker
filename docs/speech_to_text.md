# Speech-to-Text (local, faster-whisper)

Audio inputs become text and then reuse the SAME expense extraction pipeline
as typed text: there is no separate audio extraction path.

```
Audio → audio preprocessing (FFmpeg) → Speech-to-Text → transcript
      → ExpenseParser → normalization → validation → ExpenseCandidate → Playground preview
```

The Rails app depends only on the `SpeechToText` boundary, never on
faster-whisper, Python, FFmpeg, or model files directly.

## Components

| File | Role |
|------|------|
| `app/services/speech_to_text.rb` | Provider-independent boundary: `SpeechToText.transcribe(...)` + provider registry + error hierarchy |
| `app/services/speech_to_text/result.rb` | Standardized `SpeechToText::Result` (text, language, language_probability, duration, provider, model, metadata) |
| `app/services/speech_to_text/audio_preprocessor.rb` | FFmpeg normalization to WAV / 16 kHz / mono / PCM / loudness-normalized |
| `app/services/speech_to_text/whisper.rb` | Local provider: preprocesses, runs the Python process, returns a Result |
| `script/whisper_transcribe.py` | Stable CLI around faster-whisper used by the provider |

## Local setup

```sh
# 1. FFmpeg (MacPorts on this machine; on PATH in the Linux container)
ffmpeg -version

# 2. Python venv with faster-whisper
/opt/local/bin/python3.12 -m venv whisper-env
whisper-env/bin/pip install faster-whisper

# 3. Verify the installation
whisper-env/bin/python -c "from faster_whisper import WhisperModel; print('faster-whisper OK')"
```

The first transcription downloads the model (`small` ≈ 460 MB) into
`~/.cache/huggingface` — it must be warmed up once before it is usable
offline.

## Configuration

| Variable | Default | Notes |
|----------|---------|-------|
| `SPEECH_TO_TEXT_PROVIDER` | `whisper` | Future: `openai`, ... (no pipeline changes needed) |
| `WHISPER_MODEL` | `small` | `small` scored clearly better than `base` in local tests |
| `WHISPER_LANGUAGE` | (unset = auto-detect) | e.g. `es`, `en`, `pt` |
| `WHISPER_DEVICE` | `cpu` | No GPU requirements |
| `WHISPER_COMPUTE_TYPE` | `int8` | |
| `WHISPER_TIMEOUT` | `300` | Seconds before the Python process is killed |
| `WHISPER_PYTHON` | (unset) | Full path override; falls back to `whisper-env/bin/python`, then `python3` |
| `FFMPEG_BIN` | `ffmpeg` | Full path override (MacPorts: `/opt/local/bin/ffmpeg`) |

## Transcription settings (initial)

```
model: small · device: cpu · compute_type: int8
language: configurable (WHISPER_LANGUAGE, default auto-detect)
beam_size: 5 · vad_filter: false · condition_on_previous_text: false
```

## Why preprocessing is mandatory

Passing the raw OGG voice note directly to Whisper produced wrong
transcripts. After FFmpeg normalization the same audio transcribed
correctly:

```text
raw OGG  + small → "¡Hasta la próxima!"   (wrong)
FFmpeg (loudnorm, 16 kHz, mono) + small → "Este es un ejemplo."  (correct)
```

`SpeechToText::Whisper` therefore ALWAYS converts input audio with:

```sh
ffmpeg -i input.ogg \
  -af "loudnorm=I=-16:TP=-1.5:LRA=11" \
  -ar 16000 -ac 1 -f wav -c:a pcm_s16le output.wav
```

## Supported formats

`.ogg`, `.opus`, `.m4a`, `.mp3`, `.wav`, `.webm` — up to 15 MB per upload.

## Error handling

All failures surface as `SpeechToText::Error` subclasses
(`UnsupportedFormatError`, `PreprocessingError`, `TranscriptionError`,
`ProviderUnavailableError`) with application-level messages. Raw Python
stack traces are logged server-side, never shown to users.

## Production considerations / TODO

- Whisper on CPU is slow for long audio; move processing into a Solid Queue
  job (`ProcessAudioJob`) once audio leaves the Playground. The service is
  already a single `SpeechToText.transcribe` call, so no rewrite needed.
- The container image needs `ffmpeg` (added to the Dockerfile) and a
  Python runtime with `faster-whisper` + the model baked or cached.
- Model loading per invocation is fine for development; for production,
  consider a persistent worker process to avoid repeated model loads.
