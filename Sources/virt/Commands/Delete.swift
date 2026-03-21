import ArgumentParser

struct Delete: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Delete a VM and its disk image"
    )

    @Argument(help: "Name of the VM")
    var name: String

    func run() throws {
        print("Deleting VM '\(name)'")
    }
}
