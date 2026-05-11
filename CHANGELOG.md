# Changelog

All notable public-facing changes to Paddlr will be documented in this file.

## Unreleased

- No unreleased public-facing changes yet.

## 0.1.7 - 2026-05-11

### Changed

- Made the post-permission restart prompt more reliable for menu bar/agent app behavior by watching macOS frontmost-app changes and checking again when the Paddlr popover is reopened.

## 0.1.6 - 2026-05-11

### Changed

- The **Grant Controller Input Access** button now requests both macOS Input Monitoring/listen-event access and raw HID controller access.
- After either permission request sends the user away from Paddlr and the app becomes active again, Paddlr prompts the user to restart so macOS permission changes apply cleanly.

## 0.1.5 - 2026-05-11

### Changed

- Renamed the user-facing Input Monitoring row and button to **Controller Input Access** to reflect that macOS may satisfy raw controller input access through Accessibility or Input Monitoring.
- Documented that **Controller Input Access: Ready** can appear even when Paddlr is not listed separately under Input Monitoring.

## 0.1.4 - 2026-05-11

### Changed

- Changed Input Monitoring from an automatic launch prompt to an explicit **Grant Input Monitoring Permission** button flow, matching the Accessibility permission flow.
- Paddlr now waits to start raw controller detection until Input Monitoring permission is already trusted.
- Updated controller status copy to show that controller input is waiting on permission.

## 0.1.3 - 2026-05-11

### Changed

- Added an Input Monitoring permission status row and prompt button for Macs/connection paths that require it for raw controller input.
- Documented that Paddlr may need both Accessibility and Input Monitoring permissions.

## 0.1.2 - 2026-05-11

### Changed

- Reorganized the README around a Quick start flow before detailed UI/reference sections.
- Split the Gatekeeper first-launch and **Open Anyway** confirmation screenshots into separate README steps.
- Updated local bundle signing to use a stable bundle-identifier requirement for future preview updates.
- Documented that users should move `Paddlr.app` to its final location before granting Accessibility permission, and that earlier preview updates may require granting permission again.

## 0.1.1 - 2026-05-11

### Added

- Added a Gatekeeper warning screenshot and first-launch approval steps to the README.

### Changed

- Made the Accessibility permission action in the menu bar panel more prominent.
- Updated the app icon background to match the Part of a Day page background color.

## 0.1.0 - 2026-05-11

### Added

- Added the Paddlr Swift package and menu bar app for mapping Xbox Elite Series 2 paddles to keyboard output on macOS.
- Added configurable paddle mappings, named profiles, controller selection, app pinning, controller-scoped default mappings, and per-app rules that can be scoped to the selected controller.
- Added diagnostic command-line tools for controller and HID investigation.
- Added a no-dependency self-test with `swift run PaddlrSelfTest`.
- Added the Paddlr app icon and small public README logo.
- Added `scripts/release/package_app.sh` for creating `dist/Paddlr.app` and an optional convenience zip archive from source.

### Changed

- Set the package minimum platform to macOS 15 and documented that validation has only covered Apple silicon Macs so far.
- Documented that the controller should be set to Profile 0/default no-profile-LED mode for distinct paddle input.
- Added public compatibility notes for hardware coverage, controller IDs/firmware versions, Profile 0 setup, macOS native controller profile positioning, and game-specific behavior such as Cult of the Lamb input glyph switching and World of Warcraft/ConsolePort dual input.
- Renamed the project from EliteMapper to Paddlr for public release preparation.
- Made `swift run Paddlr` the primary menu bar app command and `swift run PaddlrDetect` the detection-only command.

### Known limitations

- Keyboard output is supported; virtual gamepad/Xbox button output is planned for later.
- USB wired Elite 2 paddle support is still under investigation.
- Additional controller variants, firmware versions, connection modes, and Intel Macs need validation.
