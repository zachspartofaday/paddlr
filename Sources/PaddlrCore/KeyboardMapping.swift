import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// A keyboard output mapping that can represent both built-in presets and captured keys.
public struct KeyboardMapping: Codable, Equatable, Hashable, Sendable {
    public var keyCode: CGKeyCode
    public var modifierFlagsRawValue: UInt64
    public var keyDisplayName: String

    public init(
        keyCode: CGKeyCode,
        modifierFlagsRawValue: UInt64 = 0,
        keyDisplayName: String? = nil
    ) {
        self.keyCode = keyCode
        self.modifierFlagsRawValue = modifierFlagsRawValue
        self.keyDisplayName = keyDisplayName ?? Self.defaultDisplayName(for: keyCode)
    }

    public init(syntheticKey: SyntheticKey) {
        self.init(keyCode: syntheticKey.keyCode, keyDisplayName: syntheticKey.displayName)
    }

    public var eventFlags: CGEventFlags {
        CGEventFlags(rawValue: modifierFlagsRawValue)
    }

    public var displayName: String {
        let modifiers = modifierDisplayNames
        guard !modifiers.isEmpty else {
            return keyDisplayName
        }

        return (modifiers + [keyDisplayName]).joined(separator: "+")
    }

    public static func defaultDisplayName(for keyCode: CGKeyCode) -> String {
        keyDisplayNames[keyCode] ?? "Key Code \(keyCode)"
    }

    private var modifierDisplayNames: [String] {
        let flags = eventFlags
        var names: [String] = []

        if flags.contains(.maskCommand) {
            names.append("Command")
        }
        if flags.contains(.maskShift) {
            names.append("Shift")
        }
        if flags.contains(.maskAlternate) {
            names.append("Option")
        }
        if flags.contains(.maskControl) {
            names.append("Control")
        }

        return names
    }

    private static let keyDisplayNames: [CGKeyCode: String] = [
        CGKeyCode(kVK_Escape): "Escape",
        CGKeyCode(kVK_Tab): "Tab",
        CGKeyCode(kVK_Space): "Space",
        CGKeyCode(kVK_Return): "Return",
        CGKeyCode(kVK_Delete): "Delete",
        CGKeyCode(kVK_ForwardDelete): "Forward Delete",
        CGKeyCode(kVK_Help): "Help",
        CGKeyCode(kVK_Home): "Home",
        CGKeyCode(kVK_End): "End",
        CGKeyCode(kVK_PageUp): "Page Up",
        CGKeyCode(kVK_PageDown): "Page Down",
        CGKeyCode(kVK_UpArrow): "Up Arrow",
        CGKeyCode(kVK_DownArrow): "Down Arrow",
        CGKeyCode(kVK_LeftArrow): "Left Arrow",
        CGKeyCode(kVK_RightArrow): "Right Arrow",
        CGKeyCode(kVK_ANSI_A): "A",
        CGKeyCode(kVK_ANSI_B): "B",
        CGKeyCode(kVK_ANSI_C): "C",
        CGKeyCode(kVK_ANSI_D): "D",
        CGKeyCode(kVK_ANSI_E): "E",
        CGKeyCode(kVK_ANSI_F): "F",
        CGKeyCode(kVK_ANSI_G): "G",
        CGKeyCode(kVK_ANSI_H): "H",
        CGKeyCode(kVK_ANSI_I): "I",
        CGKeyCode(kVK_ANSI_J): "J",
        CGKeyCode(kVK_ANSI_K): "K",
        CGKeyCode(kVK_ANSI_L): "L",
        CGKeyCode(kVK_ANSI_M): "M",
        CGKeyCode(kVK_ANSI_N): "N",
        CGKeyCode(kVK_ANSI_O): "O",
        CGKeyCode(kVK_ANSI_P): "P",
        CGKeyCode(kVK_ANSI_Q): "Q",
        CGKeyCode(kVK_ANSI_R): "R",
        CGKeyCode(kVK_ANSI_S): "S",
        CGKeyCode(kVK_ANSI_T): "T",
        CGKeyCode(kVK_ANSI_U): "U",
        CGKeyCode(kVK_ANSI_V): "V",
        CGKeyCode(kVK_ANSI_W): "W",
        CGKeyCode(kVK_ANSI_X): "X",
        CGKeyCode(kVK_ANSI_Y): "Y",
        CGKeyCode(kVK_ANSI_Z): "Z",
        CGKeyCode(kVK_ANSI_0): "0",
        CGKeyCode(kVK_ANSI_1): "1",
        CGKeyCode(kVK_ANSI_2): "2",
        CGKeyCode(kVK_ANSI_3): "3",
        CGKeyCode(kVK_ANSI_4): "4",
        CGKeyCode(kVK_ANSI_5): "5",
        CGKeyCode(kVK_ANSI_6): "6",
        CGKeyCode(kVK_ANSI_7): "7",
        CGKeyCode(kVK_ANSI_8): "8",
        CGKeyCode(kVK_ANSI_9): "9",
        CGKeyCode(kVK_ANSI_Minus): "-",
        CGKeyCode(kVK_ANSI_Equal): "=",
        CGKeyCode(kVK_ANSI_LeftBracket): "[",
        CGKeyCode(kVK_ANSI_RightBracket): "]",
        CGKeyCode(kVK_ANSI_Backslash): "\\",
        CGKeyCode(kVK_ANSI_Semicolon): ";",
        CGKeyCode(kVK_ANSI_Quote): "'",
        CGKeyCode(kVK_ANSI_Grave): "`",
        CGKeyCode(kVK_ANSI_Comma): ",",
        CGKeyCode(kVK_ANSI_Period): ".",
        CGKeyCode(kVK_ANSI_Slash): "/",
        CGKeyCode(kVK_F1): "F1",
        CGKeyCode(kVK_F2): "F2",
        CGKeyCode(kVK_F3): "F3",
        CGKeyCode(kVK_F4): "F4",
        CGKeyCode(kVK_F5): "F5",
        CGKeyCode(kVK_F6): "F6",
        CGKeyCode(kVK_F7): "F7",
        CGKeyCode(kVK_F8): "F8",
        CGKeyCode(kVK_F9): "F9",
        CGKeyCode(kVK_F10): "F10",
        CGKeyCode(kVK_F11): "F11",
        CGKeyCode(kVK_F12): "F12",
        CGKeyCode(kVK_F13): "F13",
        CGKeyCode(kVK_F14): "F14",
        CGKeyCode(kVK_F15): "F15",
        CGKeyCode(kVK_F16): "F16",
        CGKeyCode(kVK_F17): "F17",
        CGKeyCode(kVK_F18): "F18",
        CGKeyCode(kVK_F19): "F19",
        CGKeyCode(kVK_F20): "F20",
        CGKeyCode(kVK_Shift): "Shift",
        CGKeyCode(kVK_RightShift): "Shift",
        CGKeyCode(kVK_Control): "Control",
        CGKeyCode(kVK_RightControl): "Control",
        CGKeyCode(kVK_Option): "Option",
        CGKeyCode(kVK_RightOption): "Option",
        CGKeyCode(kVK_Command): "Command",
        CGKeyCode(kVK_RightCommand): "Command"
    ]
}
