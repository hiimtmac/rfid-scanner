import Foundation

let system: System

do {
    system = try System()
    print("Running system...")
    try system.run()
} catch {
    print("System error:", error.localizedDescription)
    // TODO: show better error in here to exit code
    exit(EXIT_FAILURE)
}

RunLoop.main.run()
