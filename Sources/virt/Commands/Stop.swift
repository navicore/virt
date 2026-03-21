import ArgumentParser
import Foundation

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stop a running VM"
    )

    @Argument(help: "Name of the VM")
    var name: String

    func run() throws {
        let dir = VMDirectory(name: name)

        guard dir.exists else {
            throw ValidationError("VM '\(name)' does not exist.")
        }

        guard FileManager.default.fileExists(atPath: dir.pidURL.path) else {
            throw ValidationError("VM '\(name)' is not running.")
        }

        let pidString = try String(contentsOf: dir.pidURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = Int32(pidString) else {
            // Corrupt PID file — clean up
            try? FileManager.default.removeItem(at: dir.pidURL)
            throw ValidationError("VM '\(name)' has a corrupt PID file. Cleaned up.")
        }

        // Check if process is actually running
        guard kill(pid, 0) == 0 else {
            // Stale PID file — clean up
            try? FileManager.default.removeItem(at: dir.pidURL)
            throw ValidationError("VM '\(name)' is not running (stale PID file removed).")
        }

        // Send SIGINT for graceful shutdown (matches the signal handler in VMInstance)
        print("Sending shutdown signal to VM '\(name)' (PID \(pid))...")
        kill(pid, SIGINT)

        // Wait up to 15 seconds for the process to exit
        let deadline = Date(timeIntervalSinceNow: 15)
        while Date() < deadline {
            if kill(pid, 0) != 0 {
                print("VM '\(name)' stopped.")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        // Escalate to SIGKILL
        print("VM did not stop gracefully, force killing...")
        kill(pid, SIGKILL)
        Thread.sleep(forTimeInterval: 1.0)

        if kill(pid, 0) != 0 {
            try? FileManager.default.removeItem(at: dir.pidURL)
            print("VM '\(name)' killed.")
        } else {
            throw ValidationError("Failed to stop VM '\(name)' (PID \(pid)).")
        }
    }
}
