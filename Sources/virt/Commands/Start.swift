import ArgumentParser

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start a VM"
    )

    @Argument(help: "Name of the VM")
    var name: String

    @Option(help: "Path to ISO image to attach")
    var iso: String? = nil

    func run() throws {
        print("Starting VM '\(name)'")
    }
}
