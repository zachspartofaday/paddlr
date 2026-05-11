import Darwin
import Foundation
import PaddlrCore

print("Paddlr Phase 1 POC")
print("Primary target: macOS 26 Tahoe")
print("Input paths: Apple GameController.framework + raw IOHID fallback")
print("Press Control-C to exit.")
print("")
fflush(stdout)

let gameControllerMonitor = GameControllerPaddleMonitor { message in
    print("[GameController] \(message)")
    fflush(stdout)
}
let hidPaddleMonitor = HIDPaddleMonitor { message in
    print("[IOHID] \(message)")
    fflush(stdout)
}

gameControllerMonitor.start()
hidPaddleMonitor.start()

RunLoop.main.run()
