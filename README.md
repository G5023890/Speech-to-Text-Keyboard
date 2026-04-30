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
- `whisper.cpp` CLI adapter with Metal and VAD flag prepared.
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

## Notes

This is a local-development milestone, not a notarized distribution build.
The default bootstrap uses Metal but disables mandatory Core ML encoder loading. Core ML acceleration should be enabled only together with matching `*-encoder.mlmodelc` artifacts for each selected model.
