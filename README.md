# Local STT

Native macOS menu bar dictation prototype for Apple Silicon.

## What is implemented

- Menu bar app with idle, recording, transcribing, and error states.
- Hold-to-talk global hotkeys:
  - `Fn + Shift`: RU+EN mixed profile.
  - `Fn + Shift + Control`: Hebrew-only profile.
- Microphone permission flow.
- Accessibility permission flow for inserting recognized text into the focused app.
- Local model manager for Whisper ggml models.
- `whisper.cpp` CLI adapter with Metal, optional Core ML encoder fallback, and VAD flag prepared.
- No transcription history. Temporary audio is deleted after transcription.

## Build and install

```sh
./scripts/build_and_install_app.sh
```

The script builds the SwiftPM executable, packages it as `/Applications/Local STT.app`, and signs it with a stable bundle id.

## Whisper runtime

Install/build `whisper.cpp` into `Vendor/whisper.cpp`:

```sh
./scripts/bootstrap_whisper_cpp.sh
```

Then open the app settings and download a model. The transcription adapter looks for:

- `Vendor/whisper.cpp/build/bin/whisper-cli`
- `Vendor/whisper.cpp/build/bin/main`
- `/opt/homebrew/bin/whisper-cli`
- `/usr/local/bin/whisper-cli`

## Core ML encoder

Core ML acceleration is optional and model-specific. Download the matching encoder for the selected model:

```sh
./scripts/download_coreml_encoder.sh small
```

This installs:

```text
~/Library/Application Support/LocalSTT/Models/ggml-small-encoder.mlmodelc
```

When this folder exists beside `ggml-small.bin`, the Core ML-enabled `whisper.cpp` build loads it automatically. If it is missing or fails to load, `WHISPER_COREML_ALLOW_FALLBACK` keeps transcription on the regular Metal path instead of failing.

## Notes

This is a local-development milestone, not a notarized distribution build.
The default bootstrap uses Metal and Core ML with fallback enabled. Core ML only activates when the matching `*-encoder.mlmodelc` artifact exists beside the selected `.bin` model.
