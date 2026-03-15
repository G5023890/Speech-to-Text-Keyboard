# Voice Input

Release: `1.6.1`

Local push-to-talk speech-to-text for macOS with a lightweight background app and configurable menu bar behavior.

## Features

- Hold a selected hotkey combination to record
- Release to transcribe locally with `whisper.cpp`
- Automatically paste text into the active app
- Choose the active transcription model
- Configure language mode
- Toggle whether the app is shown in the menu bar
- Open Settings automatically when the menu bar icon is disabled

## Requirements

- macOS `26.0+`
- Homebrew
- `ffmpeg`
- `hammerspoon`
- `whisper-cpp`

## Install

```bash
brew install ffmpeg hammerspoon whisper-cpp
```

## Checkpoints

- active restore checkpoint: `./.checkpoints/Stage-1.4`

## Project Setup

```bash
cd "/path/to/Voice input"
chmod +x scripts/ptt_whisper.sh
scripts/ptt_whisper.sh download-model
scripts/ptt_whisper.sh download-fast-model
scripts/ptt_whisper.sh download-turbo-model
scripts/ptt_whisper.sh download-large-v3-turbo-model
```

## Current Local Models

- `~/Library/Application Support/Voice Input/models/ggml-medium-q5_0.bin`
- `~/Library/Application Support/Voice Input/models/ggml-small-q5_1.bin`
- `~/Library/Application Support/Voice Input/models/ggml-large-v3-turbo-q5_0.bin`

## Build And Install

```bash
./scripts/build_and_install_app.sh
```

The app is installed to:

```text
/Applications/Voice Input.app
```

After install:

- app path: `/Applications/Voice Input.app`
- menu bar icon source: `Resources/taskbar_Mic.png`
- app icon source: `assets/AppIcon.icns`
- app stays only in the menu bar and remains hidden from the Dock
- settings open from the menu item `Настройки…`
- update flow: `Проверить обновления` shows install/update state and model versions
- update button: `Обновить модели`

## Settings

The app provides a Settings window with:

- Launch at login
- Show in menu bar
- Hotkey selection
- Language mode
- Model selection and model management
- Quality mode
- Recording time limit
- Usage statistics

## Menu Bar Behavior

If **Show in menu bar** is enabled:

- the app shows its status icon in the macOS menu bar
- Settings can be opened from the menu bar menu

If **Show in menu bar** is disabled:

- the status icon is hidden
- the app stays running as a background accessory app
- Settings does not open on the first launch
- reopening the app shows Settings again

## Hotkey

Supported hotkey modes:

- `Shift+Option`
- `Shift+Control`
- `Shift+Command`
- `Shift+Fn`
- `Fn`

Menu bar workflow:

- choose hotkey in `Voice Input -> Hotkey`
- choose transcription model in `Voice Input -> Модель`
- available menu bar model options include `medium-q5_0`, `small-q5_1`, and `large-v3-turbo-q5_0`

## Language Settings

Defaults in `scripts/ptt_whisper.sh`:

- `WHISPER_LANGUAGE=auto`
- prompt hint for Russian/English/Hebrew switching

Optional override:

```bash
WHISPER_MODEL="/path/to/ggml-small.bin" \
WHISPER_LANGUAGE="auto" \
WHISPER_PROMPT="The speaker may switch between Russian, English, and Hebrew."
```

Set these in your shell profile before launching `Voice Input.app`, or edit defaults in `scripts/ptt_whisper.sh`.
If you want explicit single-language mode, set `WHISPER_LANGUAGE=ru`.

## Term Glossary

To improve recognition of names and terms, edit:

- `./config/glossary.txt`

Rules:

- one term per line
- lines starting with `#` are comments
- the file is auto-included in the transcription prompt

## Speed Tuning

- default profile is `WHISPER_PROFILE=balanced` and prefers `medium-q5_0`
- profiles: `fast`, `balanced`, `quality`
- `fast` resolution order: `small-q5_1` -> `small` -> `medium-q5_0` -> `medium`
- `balanced` resolution order: `medium-q5_0` -> `medium`
- `quality` resolution order: `medium` -> `medium-q5_0`
- uses `WHISPER_THREADS` and defaults to CPU core count
- fast decode defaults: `WHISPER_BEAM_SIZE=1`, `WHISPER_BEST_OF=1`
- `--vad` is disabled by default for stability on some builds

Enable VAD only if you also provide a valid VAD model:

```bash
WHISPER_VAD=1
```

Recommended local settings:

```bash
WHISPER_PROFILE=balanced
WHISPER_THREADS=6
WHISPER_BEAM_SIZE=1
WHISPER_BEST_OF=1
```

## Notes

- The app uses a local `whisper.cpp` installation from Homebrew
- The current build target is aligned to macOS `26.0`
- The app runs as a menu bar/accessory-style macOS app rather than a Dock-first app

## License

SPDX-License-Identifier: Apache-2.0

See `~/Documents/Develop/Voice input/LICENSE`.
