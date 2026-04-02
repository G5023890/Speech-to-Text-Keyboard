# Voice Input Release Notes

## 0.0.1 installer bundle

This release ships a self-contained macOS installer:

- `dist/Voice Input.dmg`
- `Voice Input.app` bundled with runtime dependencies
- fixed hotkey profiles:
  - `Shift+Fn` for `RU/EN`
  - `Shift+Control+Fn` for `עברית`
- safer native decode isolation so a ggml abort does not take down the UI process
- bundled CLI fallback and bundled backend plugins inside the app package
- model quality warning for the default `small-q8_0` setup

## Notes

- The installer is produced by `scripts/create_dmg.sh`.
- The app version is `0.0.1`.
- The current build is intended for macOS `26.0+`.
