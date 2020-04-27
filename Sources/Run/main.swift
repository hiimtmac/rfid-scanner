import Foundation

let system: System

do {
    system = try System()
    print("Running system...")
    try system.run()
} catch let error as SystemError {
    print("System error:", error.localizedDescription)
    exit(error.errorCode)
} catch {
    print("Unknown error:", error.localizedDescription)
    exit(EXIT_FAILURE)
}

signal(SIGINT, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler {
    print("Something killed me...")
    system.cleanup()
    exit(EXIT_SUCCESS)
}
sigint.resume()

RunLoop.main.run()
