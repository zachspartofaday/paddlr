# Compatibility Notes

This document tracks hardware, macOS, connection, controller-profile, and game-specific behavior observed while testing Paddlr.

Paddlr is intended as a lightweight companion to macOS's native controller profiles. Use macOS's built-in controller profile support for rebinding standard Xbox buttons; use Paddlr for Elite back-paddle to keyboard mappings.

## Tested baseline

| Area | Current status |
|---|---|
| macOS | macOS 26 Tahoe is the primary validation target. Paddlr requires macOS 15 or newer. |
| Mac hardware | Tested on Apple silicon Macs. Intel Macs are not yet validated. |
| Controller | Xbox Elite Series 2 over Bluetooth. Additional controller variants and firmware versions need validation. |
| Controller profile | Use **Profile 0** / no profile LEDs for distinct paddle input. |
| Output | Keyboard output through macOS Accessibility permission. Virtual gamepad/Xbox button output is not implemented yet. |

## Controller IDs and firmware versions

Known and candidate controller identifiers are tracked here so compatibility reports can be tied to specific hardware/firmware combinations.

| Controller / reported product | Transport | Vendor ID | Product ID | Firmware | Status | Notes |
|---|---|---:|---:|---|---|---|
| Xbox Wireless Controller / Xbox Elite Series 2 | Bluetooth LE | `0x045e` | `0x0b22` | `5.24.4.0` | Validated | Raw IOHID paddle bits were observed on macOS 26 Tahoe. Profile 0 produced the cleanest behavior. |
| Controller / Xbox Elite Series 2 | USB | `0x045e` | `0x0b00` | Unknown | Under investigation | Device identity was observed over USB, but unique wired paddle support still needs a lower-level backend. |
| Xbox Elite Series 2 Core or related variant | Unknown | `0x045e` | `0x0b05` | Unknown | Needs validation | Known Elite-family product ID candidate; not validated in this project yet. |

When reporting compatibility, include the controller's vendor ID, product ID, firmware version, transport, and active profile slot whenever possible.

## Controller profile guidance

Set the Xbox Elite Series 2 controller to **Profile 0** before using Paddlr. Profile 0 is the default/no-profile-LED mode.

Profiles 1-3 can emit the controller's firmware-mapped buttons in addition to paddle information. In games, that can look like both the original controller button and Paddlr's keyboard mapping fired from the same paddle press.

## Game-specific notes

| Game/app | Status | Notes |
|---|---|---|
| Cult of the Lamb | Known glyph-switching behavior | The game dynamically switches visible input prompts based on the most recent input method. Pressing paddles mapped to keyboard keys can temporarily show keyboard prompts, while normal Xbox controller buttons can switch prompts back to Xbox glyphs. |
| World of Warcraft with ConsolePort | Known dual-input behavior | ConsolePort can detect Elite paddles natively. If the paddles are also mapped to keyboard binds and Paddlr is enabled for World of Warcraft, the game/add-on can receive both the native paddle input and Paddlr's keyboard output. Disable Paddlr for World of Warcraft or avoid duplicate binds when using ConsolePort's native paddle support. |

## General gameplay notes

- Paddlr does not replace macOS's native controller profiles for standard Xbox button rebinding.
- Paddlr does not suppress native controller input; it adds keyboard output when paddle input is detected.
- Games that listen directly to controller input may still see the controller's own signals.
- Games with dynamic input-method detection may switch visible prompts between keyboard/mouse and controller glyphs while you play.
- Games or add-ons that natively detect Elite paddles can receive dual inputs if Paddlr is also enabled and mapping those paddles to keyboard binds.
- Xbox Wireless Adapter support is not expected on macOS.

## Reporting compatibility results

When reporting a compatibility result, include:

- Mac model and CPU family, e.g. Apple silicon or Intel.
- macOS version.
- Controller model and firmware version if available.
- Connection type: Bluetooth, USB, or other.
- Controller profile slot: Profile 0, 1, 2, or 3.
- Game/app name and version.
- Whether paddle input was distinct, duplicated, missing, or caused prompt/glyph switching.
