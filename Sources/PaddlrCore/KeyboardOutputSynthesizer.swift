import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Keyboard keys available as paddle mapping outputs.
public enum SyntheticKey: String, CaseIterable, Sendable {
    case escape = "Escape"
    case tab = "Tab"
    case space = "Space"
    case returnKey = "Return"
    case delete = "Delete"
    case forwardDelete = "Forward Delete"

    case upArrow = "Up Arrow"
    case downArrow = "Down Arrow"
    case leftArrow = "Left Arrow"
    case rightArrow = "Right Arrow"

    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
    case e = "E"
    case f = "F"
    case g = "G"
    case h = "H"
    case i = "I"
    case j = "J"
    case k = "K"
    case l = "L"
    case m = "M"
    case n = "N"
    case o = "O"
    case p = "P"
    case q = "Q"
    case r = "R"
    case s = "S"
    case t = "T"
    case u = "U"
    case v = "V"
    case w = "W"
    case x = "X"
    case y = "Y"
    case z = "Z"

    case zero = "0"
    case one = "1"
    case two = "2"
    case three = "3"
    case four = "4"
    case five = "5"
    case six = "6"
    case seven = "7"
    case eight = "8"
    case nine = "9"

    case f1 = "F1"
    case f2 = "F2"
    case f3 = "F3"
    case f4 = "F4"
    case f5 = "F5"
    case f6 = "F6"
    case f7 = "F7"
    case f8 = "F8"
    case f9 = "F9"
    case f10 = "F10"
    case f11 = "F11"
    case f12 = "F12"
    case f13 = "F13"
    case f14 = "F14"
    case f15 = "F15"
    case f16 = "F16"
    case f17 = "F17"
    case f18 = "F18"
    case f19 = "F19"
    case f20 = "F20"

    case shift = "Shift"
    case control = "Control"
    case option = "Option"
    case command = "Command"

    public var displayName: String {
        rawValue
    }

    public var keyboardMapping: KeyboardMapping {
        KeyboardMapping(syntheticKey: self)
    }

    public var keyCode: CGKeyCode {
        switch self {
        case .escape:
            return CGKeyCode(kVK_Escape)
        case .tab:
            return CGKeyCode(kVK_Tab)
        case .space:
            return CGKeyCode(kVK_Space)
        case .returnKey:
            return CGKeyCode(kVK_Return)
        case .delete:
            return CGKeyCode(kVK_Delete)
        case .forwardDelete:
            return CGKeyCode(kVK_ForwardDelete)
        case .upArrow:
            return CGKeyCode(kVK_UpArrow)
        case .downArrow:
            return CGKeyCode(kVK_DownArrow)
        case .leftArrow:
            return CGKeyCode(kVK_LeftArrow)
        case .rightArrow:
            return CGKeyCode(kVK_RightArrow)
        case .a:
            return CGKeyCode(kVK_ANSI_A)
        case .b:
            return CGKeyCode(kVK_ANSI_B)
        case .c:
            return CGKeyCode(kVK_ANSI_C)
        case .d:
            return CGKeyCode(kVK_ANSI_D)
        case .e:
            return CGKeyCode(kVK_ANSI_E)
        case .f:
            return CGKeyCode(kVK_ANSI_F)
        case .g:
            return CGKeyCode(kVK_ANSI_G)
        case .h:
            return CGKeyCode(kVK_ANSI_H)
        case .i:
            return CGKeyCode(kVK_ANSI_I)
        case .j:
            return CGKeyCode(kVK_ANSI_J)
        case .k:
            return CGKeyCode(kVK_ANSI_K)
        case .l:
            return CGKeyCode(kVK_ANSI_L)
        case .m:
            return CGKeyCode(kVK_ANSI_M)
        case .n:
            return CGKeyCode(kVK_ANSI_N)
        case .o:
            return CGKeyCode(kVK_ANSI_O)
        case .p:
            return CGKeyCode(kVK_ANSI_P)
        case .q:
            return CGKeyCode(kVK_ANSI_Q)
        case .r:
            return CGKeyCode(kVK_ANSI_R)
        case .s:
            return CGKeyCode(kVK_ANSI_S)
        case .t:
            return CGKeyCode(kVK_ANSI_T)
        case .u:
            return CGKeyCode(kVK_ANSI_U)
        case .v:
            return CGKeyCode(kVK_ANSI_V)
        case .w:
            return CGKeyCode(kVK_ANSI_W)
        case .x:
            return CGKeyCode(kVK_ANSI_X)
        case .y:
            return CGKeyCode(kVK_ANSI_Y)
        case .z:
            return CGKeyCode(kVK_ANSI_Z)
        case .zero:
            return CGKeyCode(kVK_ANSI_0)
        case .one:
            return CGKeyCode(kVK_ANSI_1)
        case .two:
            return CGKeyCode(kVK_ANSI_2)
        case .three:
            return CGKeyCode(kVK_ANSI_3)
        case .four:
            return CGKeyCode(kVK_ANSI_4)
        case .five:
            return CGKeyCode(kVK_ANSI_5)
        case .six:
            return CGKeyCode(kVK_ANSI_6)
        case .seven:
            return CGKeyCode(kVK_ANSI_7)
        case .eight:
            return CGKeyCode(kVK_ANSI_8)
        case .nine:
            return CGKeyCode(kVK_ANSI_9)
        case .f1:
            return CGKeyCode(kVK_F1)
        case .f2:
            return CGKeyCode(kVK_F2)
        case .f3:
            return CGKeyCode(kVK_F3)
        case .f4:
            return CGKeyCode(kVK_F4)
        case .f5:
            return CGKeyCode(kVK_F5)
        case .f6:
            return CGKeyCode(kVK_F6)
        case .f7:
            return CGKeyCode(kVK_F7)
        case .f8:
            return CGKeyCode(kVK_F8)
        case .f9:
            return CGKeyCode(kVK_F9)
        case .f10:
            return CGKeyCode(kVK_F10)
        case .f11:
            return CGKeyCode(kVK_F11)
        case .f12:
            return CGKeyCode(kVK_F12)
        case .f13:
            return CGKeyCode(kVK_F13)
        case .f14:
            return CGKeyCode(kVK_F14)
        case .f15:
            return CGKeyCode(kVK_F15)
        case .f16:
            return CGKeyCode(kVK_F16)
        case .f17:
            return CGKeyCode(kVK_F17)
        case .f18:
            return CGKeyCode(kVK_F18)
        case .f19:
            return CGKeyCode(kVK_F19)
        case .f20:
            return CGKeyCode(kVK_F20)
        case .shift:
            return CGKeyCode(kVK_Shift)
        case .control:
            return CGKeyCode(kVK_Control)
        case .option:
            return CGKeyCode(kVK_Option)
        case .command:
            return CGKeyCode(kVK_Command)
        }
    }
}

/// Uses CoreGraphics to post synthetic keyboard events.
public final class KeyboardOutputSynthesizer {
    private let log: (String) -> Void

    public convenience init() {
        self.init(log: KeyboardOutputSynthesizer.defaultLog(_:))
    }

    public init(log: @escaping (String) -> Void) {
        self.log = log
    }

    /// Returns whether the current host process is trusted for Accessibility APIs.
    /// When `prompt` is true, macOS may show a System Settings permission prompt.
    public static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Posts one key-down or key-up event for a built-in key preset.
    public func setKey(_ key: SyntheticKey, isPressed: Bool) {
        setKeyboard(key.keyboardMapping, isPressed: isPressed)
    }

    /// Posts one key-down or key-up event for a keyboard mapping.
    public func setKeyboard(_ mapping: KeyboardMapping, isPressed: Bool) {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: mapping.keyCode,
            keyDown: isPressed
        ) else {
            log("Unable to create CGEvent for \(mapping.displayName).")
            return
        }

        event.flags = mapping.eventFlags
        event.post(tap: .cghidEventTap)
        let state = isPressed ? "down" : "up"
        log("Posted \(mapping.displayName) \(state).")
    }

    private static func defaultLog(_ message: String) {
        print(message)
        fflush(stdout)
    }
}
