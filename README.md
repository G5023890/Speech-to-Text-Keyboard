# Voice Input (Menu Bar PTT, ru+en+he)

Release: `1.0`

Local push-to-talk speech-to-text for macOS:
- hold selected hotkey combo to record
- release key to transcribe with local `whisper.cpp`
- text auto-pastes into active app

## Checkpoints

- active restore checkpoint: `./.checkpoints/Stage-1.4`

## Install

```bash
brew install ffmpeg hammerspoon whisper-cpp
```

## Project setup

```bash
cd "/path/to/Voice input"
chmod +x scripts/ptt_whisper.sh
scripts/ptt_whisper.sh download-model
scripts/ptt_whisper.sh download-fast-model
scripts/ptt_whisper.sh download-turbo-model
scripts/ptt_whisper.sh download-large-v3-turbo-model
```

Current local models:
- `~/Library/Application Support/Voice Input/models/ggml-medium-q5_0.bin`
- `~/Library/Application Support/Voice Input/models/ggml-small-q5_1.bin`
- `~/Library/Application Support/Voice Input/models/ggml-large-v3-turbo-q5_0.bin`

## Hotkey

- active app supports selectable hotkeys:
  - `Shift+Option`
  - `Shift+Control`
  - `Shift+Command`
  - `Shift+Fn`
  - `Fn`
- choose in menu bar: `Voice Input -> Hotkey`
- transcription model is selectable in menu bar: `Voice Input -> Модель` (`medium-q5_0` / `small-q5_1` / `large-v3-turbo-q5_0`)

## Native macOS app build

Build and install app bundle:

```bash
cd "/path/to/Voice input"
./scripts/build_and_install_app.sh
```

After install:
- app path: `/Applications/Voice Input.app`
- menu bar icon source: `Resources/taskbar_Mic.png`
- app icon source: `assets/AppIcon.icns`
- app stays only in menu bar (hidden from Dock)
- settings are in menu: `Настройки`
- hotkey is selectable: `Shift+Option`, `Shift+Control`, `Shift+Command`, `Shift+Fn`, `Fn`
- update flow: `Проверить обновления` shows install/update state and versions for models
- update button: `Обновить модели`

## Language settings (ru+en+he)

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
If you want explicit single language mode, set `WHISPER_LANGUAGE=ru`.

## Term glossary (recommended)

To improve recognition of names/terms, edit:
- `./config/glossary.txt`

Rules:
- one term per line
- `#` lines are comments
- file is auto-included in transcription prompt

## Speed tuning (low quality loss)

- default profile is `WHISPER_PROFILE=balanced` (prefers `medium-q5_0`)
- profiles:
  - `fast`: `small-q5_1` -> `small` -> `medium-q5_0` -> `medium`
  - `balanced`: `medium-q5_0` -> `medium`
  - `quality`: `medium` -> `medium-q5_0`
- uses `WHISPER_THREADS` (defaults to CPU cores)
- fast decode defaults: `WHISPER_BEAM_SIZE=1`, `WHISPER_BEST_OF=1`
- `--vad` is disabled by default for stability on some builds

Enable VAD only if you also provide a valid VAD model:

```bash
WHISPER_VAD=1
```

Recommended for your case (prefer `medium-q5_0`):

```bash
WHISPER_PROFILE=balanced
WHISPER_THREADS=6
WHISPER_BEAM_SIZE=1
WHISPER_BEST_OF=1
```

## License

SPDX-License-Identifier: Apache-2.0

See `/Users/grigorymordokhovich/Documents/Develop/Voice input/LICENSE`.
