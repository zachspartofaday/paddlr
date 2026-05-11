# Paddlr

Paddlr is a macOS menu bar utility for using the four back paddles on an Xbox Elite Series 2 controller as distinct keyboard shortcuts.

It is currently focused on safe keyboard output: each paddle can send a configurable key such as F13-F16, arrows, letters, numbers, or modifiers.

## Screenshots

> Screenshots will be added before the public release.

![Paddlr menu bar placeholder](assets/screenshots/paddlr-menu-bar-placeholder.svg)

![Paddlr mapping editor placeholder](assets/screenshots/paddlr-mapping-editor-placeholder.svg)

![Paddlr controller profile placeholder](assets/screenshots/paddlr-controller-profile-placeholder.svg)

## Current status

- Primary target: macOS 26 Tahoe
- Minimum Swift package platform: macOS 11
- Primary app: `Paddlr`
- Output today: keyboard events through macOS Accessibility permission
- Default mappings:
  - Paddle 1 -> F13
  - Paddle 2 -> F14
  - Paddle 3 -> F15
  - Paddle 4 -> F16

## Build and run

Build and run the self-test:

```bash
swift build
swift run PaddlrSelfTest
```

Run the menu bar app:

```bash
swift run Paddlr
```

The app appears as an icon in the macOS menu bar. Click the icon to open the mapping panel.

## Permissions

Paddlr uses CoreGraphics keyboard events for output. macOS may require Accessibility permission for the terminal or host app that launches it:

```text
System Settings -> Privacy & Security -> Accessibility
```

If the app launches from Terminal, grant Accessibility permission to Terminal or the `swift` host.

## Diagnostics

Diagnostic helper labels are hidden by default. To show extra output/profile helper text while validating behavior, launch with either:

```bash
PADDLR_DIAGNOSTIC_UI=1 swift run Paddlr
swift run Paddlr -- --diagnostic-ui
```

Live console logging is also off by default. Enable it with:

```bash
PADDLR_DEBUG_LOG=1 swift run Paddlr
```

Additional command-line tools are included for troubleshooting:

```bash
swift run PaddlrDetect
swift run PaddlrDiagnostics
swift run PaddlrHIDProbe
swift run PaddlrRawReportProbe
```

## Known issues and planned features

- **Xbox/gamepad button output is planned.** Paddlr currently sends keyboard output, not virtual gamepad buttons such as A/B/X/Y.
- **USB wired Elite 2 support needs more work.** Bluetooth paddle input works through the currently validated path; a lower-level USB backend is still under investigation.
- **More controller variants need validation.** Additional Elite controller models, firmware versions, and connection modes should be tested before broad compatibility claims.
- **Left/right modifier-specific mappings are planned.** Current modifier mappings are generic Shift/Control/Option/Command rather than side-specific variants.

## Limitations

- Paddlr does not suppress native controller input. It adds keyboard output when paddle input is detected.
- Games that listen directly to controller input may still see the controller's own signals.
- Xbox Wireless Adapter support is not expected on macOS.
- App bundle packaging/signing/notarization is not included yet.

## License

MIT License. See [LICENSE](LICENSE).
