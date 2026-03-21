import ArgumentParser
import Foundation
import Virtualization

struct Create: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a new VM"
    )

    @Argument(help: "Name of the VM")
    var name: String

    @Option(help: "Disk size in GB")
    var disk: Int = 10

    @Option(help: "Number of CPU cores")
    var cpus: Int = 2

    @Option(help: "Memory in MB")
    var memory: Int = 2048

    func validate() throws {
        guard cpus >= 1 else {
            throw ValidationError("--cpus must be at least 1")
        }
        guard memory >= 512 else {
            throw ValidationError("--memory must be at least 512 MB")
        }
        guard disk >= 1 else {
            throw ValidationError("--disk must be at least 1 GB")
        }
    }

    func run() throws {
        let dir = VMDirectory(name: name)

        guard !dir.exists else {
            throw ValidationError("VM '\(name)' already exists.")
        }

        do {
            try dir.create()

            // Write config
            let config = VMConfig(
                name: name,
                cpus: cpus,
                memoryMB: memory,
                diskSizeGB: disk
            )
            try config.write(to: dir.configURL)

            // Allocate raw disk image (sparse — actual disk usage is near zero until written)
            let diskSizeBytes = UInt64(disk) * 1024 * 1024 * 1024
            try Data().write(to: dir.diskURL)
            let handle = try FileHandle(forWritingTo: dir.diskURL)
            try handle.truncate(atOffset: diskSizeBytes)
            try handle.close()

            // Initialize EFI variable store
            _ = try VZEFIVariableStore(creatingVariableStoreAt: dir.nvramURL)
        } catch {
            try? dir.remove()
            throw error
        }

        print("Created VM '\(name)'")
        print("  CPUs:   \(cpus)")
        print("  Memory: \(memory) MB")
        print("  Disk:   \(disk) GB")
        print("  Path:   \(dir.rootURL.path)")
    }
}
