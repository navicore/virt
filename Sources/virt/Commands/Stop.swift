import ArgumentParser

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stop a running VM"
    )

    @Argument(help: "Name of the VM")
    var name: String

    func run() throws {
        print("Stopping VM '\(name)'")
    }
}
