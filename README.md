# Local STT

Native macOS menu bar dictation app for Apple Silicon. The app records only while a hotkey is active, transcribes locally with `whisper.cpp`, and inserts the result into the focused text field.

## Current Features

- Menu bar app with idle, recording, training, transcribing, and error states.
- Built-in base model: **Whisper Small only**.
- RU+EN mixed dictation profile with Whisper language auto-detection.
- Hebrew-only dictation profile with `language=he`.
- Global hotkeys:
  - `Fn + Shift`: hold to dictate RU+EN.
  - `Fn + Shift + Control`: hold to dictate Hebrew.
  - double-tap `Control`: toggle training capture.
- Microphone permission flow.
- Accessibility permission flow for inserting recognized text into the active app.
- Local model manager for `ggml-small.bin`.
- Optional Core ML encoder download for `ggml-small-encoder.mlmodelc`.
- `whisper.cpp` runtime with Metal and Core ML fallback support.
- VAD toggle with automatic retry without VAD if the current Metal/VAD path fails.
- No transcription history. Temporary dictation audio is deleted after transcription.

## Build And Install

Build and install the app into `/Applications/Local STT.app`:

```sh
./scripts/build_and_install_app.sh
```

The script:

- builds the SwiftPM executable
- packages a macOS `.app`
- copies `whisper-cli` and its dylibs when `Vendor/whisper.cpp` is available
- copies `Resources/AppIcon.icns`
- signs with `Developer ID Application` when available, otherwise falls back to Apple Development or ad-hoc signing

## Whisper Runtime

Build `whisper.cpp` locally:

```sh
./scripts/bootstrap_whisper_cpp.sh
```

The bootstrap uses:

- Metal enabled
- Core ML enabled
- Core ML fallback enabled

The transcription adapter looks for `whisper-cli` in:

- app bundle resources
- `Vendor/whisper.cpp/build/bin/whisper-cli`
- `Vendor/whisper.cpp/build/bin/main`
- `/opt/homebrew/bin/whisper-cli`
- `/usr/local/bin/whisper-cli`

## Models

The app intentionally exposes only Whisper Small as the built-in base model:

```text
~/Library/Application Support/LocalSTT/Models/ggml-small.bin
```

Download it from Settings or the menu bar item.

Optional Core ML acceleration uses:

```text
~/Library/Application Support/LocalSTT/Models/ggml-small-encoder.mlmodelc
```

Download the Core ML encoder from Settings or run:

```sh
./scripts/download_coreml_encoder.sh small
```

When the encoder folder exists beside `ggml-small.bin`, the Core ML-enabled `whisper.cpp` build loads it automatically. If it is missing or fails to load, `WHISPER_COREML_ALLOW_FALLBACK` keeps transcription on the regular Metal path.

## Training Workflow

Training capture is local-only until explicit export.

1. Select the capture profile in Settings -> Training.
2. Double-tap `Control` to start training capture.
3. Double-tap `Control` again to stop.
4. Review and correct the transcript.
5. Save the example.

Training examples are stored under:

```text
~/Library/Application Support/LocalSTT/Training
```

Settings -> Training includes:

- RU+EN and Hebrew example counts
- dataset export
- trained model import
- manual trained-model toggle
- training reset

Reset Training deletes only collected examples, exported metadata, and imported trained models. It does not delete the base Whisper Small model or its base Core ML encoder.

See [docs/training_pipeline.md](docs/training_pipeline.md) for the external fine-tune/export/import flow.

## Distribution

Create local distribution artifacts:

```sh
./scripts/package_for_distribution.sh
```

This creates:

```text
dist/Local STT.zip
dist/Local STT.dmg
```

Notarize and staple the DMG:

```sh
APPLE_ID="you@example.com" APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx" ./scripts/notarize_distribution.sh
```

or with a saved notary profile:

```sh
NOTARY_PROFILE="profile-name" ./scripts/notarize_distribution.sh
```

After notarization, Gatekeeper should report `source=Notarized Developer ID`.

## Notes

- Target environment: Apple Silicon macOS.
- Current app style follows Apple Liquid Glass where available.
- VAD remains experimental in this build because the current `whisper.cpp` Metal/VAD path has been observed to fail on the target machine.
- The app does not train on-device. It exports reviewed examples for external GPU fine-tuning and imports the resulting `.bin` plus optional `.mlmodelc`.
