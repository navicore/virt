import ArgumentParser
import Foundation

struct Delete: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Delete a VM and its disk image"
    )

    @Argument(help: "Name of the VM")
    var name: String

    @Flag(help: "Skip confirmation prompt")
    var force: Bool = false

    func run() throws {
        let dir = VMDirectory(name: name)

        guard dir.exists else {
            throw ValidationError("VM '\(name)' does not exist.")
        }

        // Refuse to delete a running VM
        if FileManager.default.fileExists(atPath: dir.pidURL.path),
           let pidString = try? String(contentsOf: dir.pidURL, encoding: .utf8)
               .trimmingCharacters(in: .whitespacesAndNewlines),
           let pid = Int32(pidString),
           kill(pid, 0) == 0 {
            throw ValidationError("VM '\(name)' is running (PID \(pid)). Stop it first.")
        }

        if !force {
            print("Delete VM '\(name)' and all its data? [y/N] ", terminator: "")
            guard let response = readLine(), response.lowercased() == "y" else {
                print("Cancelled.")
                return
            }
        }

        try dir.remove()
        print("Deleted VM '\(name)'.")
    }
}
