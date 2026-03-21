import ArgumentParser

struct Create: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a new VM"
    )

    @Argument(help: "Name of the VM")
    var name: String

    @Option(help: "Path to ISO image")
    var iso: String? = nil

    @Option(help: "Disk size in GB")
    var disk: Int = 10

    @Option(help: "Number of CPU cores")
    var cpus: Int = 2

    @Option(help: "Memory in MB")
    var memory: Int = 2048

    func run() throws {
        print("Creating VM '\(name)' (disk: \(disk)GB, cpus: \(cpus), memory: \(memory)MB)")
    }
}
