import ArgumentParser
import Foundation

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Boot a VM with a GUI window (for install or configuration)"
    )

    @Argument(help: "Name of the VM")
    var name: String

    @Option(help: "Path to ISO image to attach")
    var iso: String? = nil

    func run() throws {
        let dir = VMDirectory(name: name)

        guard dir.exists else {
            throw ValidationError("VM '\(name)' does not exist. Run 'virt create' first.")
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

        fputs("Booting VM '\(name)' with GUI...\n", stderr)
        if let iso = iso {
            fputs("  ISO: \(iso)\n", stderr)
        }
        fputs("  CPUs: \(config.cpus), Memory: \(config.memoryMB) MB\n", stderr)

        let instance = VMInstance(config: config, dir: dir, isoPath: iso)
        let app = InstallerApp(vmInstance: instance)
        try app.run()
    }
}
