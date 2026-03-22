import ArgumentParser
import Foundation

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start a VM (headless, console in terminal)"
    )

    @Argument(help: "Name of the VM")
    var name: String

    @Option(help: "Host directory to share with the VM")
    var share: String? = nil

    func run() throws {
        let dir = VMDirectory(name: name)

        guard dir.exists else {
            throw ValidationError("VM '\(name)' does not exist.")
        }

        // Check if already running
        if FileManager.default.fileExists(atPath: dir.pidURL.path) {
            let pidString = try String(contentsOf: dir.pidURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            if let pid = Int32(pidString), kill(pid, 0) == 0 {
                throw ValidationError("VM '\(name)' is already running (PID \(pid)).")
            }
            try? FileManager.default.removeItem(at: dir.pidURL)
        }

        let config = try VMConfig.load(from: dir.configURL)

        fputs("Starting VM '\(name)'...\n", stderr)
        fputs("  CPUs: \(config.cpus), Memory: \(config.memoryMB) MB\n", stderr)
        fputs("  Console attached (hvc0). Use 'virt stop \(name)' to shut down.\n", stderr)

        if let share = share {
            fputs("  Shared folder: \(share) (mount with: mount -t virtiofs share /mnt)\n", stderr)
        }

        let instance = VMInstance(config: config, dir: dir, isoPath: nil, sharePath: share)
        try instance.runHeadless()
    }
}
