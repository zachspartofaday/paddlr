# Changelog

All notable public-facing changes to Paddlr will be documented in this file.

## Unreleased

### Added

- Added the Paddlr Swift package and menu bar app for mapping Xbox Elite Series 2 paddles to keyboard output on macOS.
- Added configurable paddle mappings, named profiles, per-app rules, controller selection, and controller-specific profile assignment.
- Added diagnostic command-line tools for controller and HID investigation.
- Added a no-dependency self-test with `swift run PaddlrSelfTest`.

### Changed

- Set the package minimum platform to macOS 15 and documented that validation has only covered Apple silicon Macs so far.
- Documented that the controller should be set to Profile 0/default no-profile-LED mode for distinct paddle input.
- Added public compatibility notes for hardware coverage, Profile 0 setup, macOS native controller profile positioning, and game-specific behavior such as Cult of the Lamb input glyph switching and World of Warcraft/ConsolePort dual input.
- Renamed the project from EliteMapper to Paddlr for public release preparation.
- Made `swift run Paddlr` the primary menu bar app command and `swift run PaddlrDetect` the detection-only command.

### Known limitations

- Keyboard output is supported; virtual gamepad/Xbox button output is planned for later.
- USB wired Elite 2 paddle support is still under investigation.
- Additional controller variants, firmware versions, connection modes, and Intel Macs need validation.
