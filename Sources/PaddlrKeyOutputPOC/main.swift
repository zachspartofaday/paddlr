import Darwin
import Foundation
import PaddlrCore

func flushPrint(_ message: String = "") {
    print(message)
    fflush(stdout)
}

let defaultMappings: [Paddle: SyntheticKey] = [
    .one: .f13,
    .two: .f14,
    .three: .f15,
    .four: .f16
]

flushPrint("Paddlr Keyboard Output POC")
flushPrint("Primary target: macOS 26 Tahoe")
flushPrint("Input path: raw IOHID Xbox Elite paddle bitmask")
flushPrint("Output path: CoreGraphics CGEvent keyboard synthesis")
flushPrint("Press Control-C to exit.")
flushPrint("")

flushPrint("Default mappings:")
for paddle in Paddle.allCases {
    if let key = defaultMappings[paddle] {
        flushPrint("- \(paddle.consoleName) -> \(key.displayName)")
    }
}
flushPrint("")

let accessibilityTrusted = KeyboardOutputSynthesizer.isAccessibilityTrusted(prompt: true)
if accessibilityTrusted {
    flushPrint("Accessibility permission: trusted")
} else {
    flushPrint("Accessibility permission: not trusted yet")
    flushPrint("If macOS opens System Settings, grant Accessibility permission to your terminal app, then rerun this command.")
    flushPrint("The POC will still log paddle events, but posted key events may not reach other apps until permission is granted.")
}
flushPrint("")

let synthesizer = KeyboardOutputSynthesizer { message in
    flushPrint("[Keyboard] \(message)")
}

let monitor = HIDPaddleMonitor(
    log: { message in
        flushPrint("[IOHID] \(message)")
    },
    onPaddleChange: { paddle, isPressed in
        guard let key = defaultMappings[paddle] else {
            flushPrint("[Keyboard] No key mapping for \(paddle.consoleName).")
            return
        }

        let paddleState = isPressed ? "pressed" : "released"
        flushPrint("[Mapping] \(paddle.consoleName) \(paddleState) -> \(key.displayName)")
        synthesizer.setKey(key, isPressed: isPressed)
    }
)

monitor.start()
RunLoop.main.run()
