# Changelog

All notable public-facing changes to Paddlr will be documented in this file.

## Unreleased

### Added

- Added the Paddlr Swift package and menu bar app for mapping Xbox Elite Series 2 paddles to keyboard output on macOS.
- Added configurable paddle mappings, named profiles, per-app rules, controller selection, and controller-specific profile assignment.
- Added diagnostic command-line tools for controller and HID investigation.
- Added a no-dependency self-test with `swift run PaddlrSelfTest`.

### Changed

- Renamed the project from EliteMapper to Paddlr for public release preparation.
- Made `swift run Paddlr` the primary menu bar app command and `swift run PaddlrDetect` the detection-only command.

### Known limitations

- Keyboard output is supported; virtual gamepad/Xbox button output is planned for later.
- USB wired Elite 2 paddle support is still under investigation.
- Additional controller variants and firmware versions need validation.
