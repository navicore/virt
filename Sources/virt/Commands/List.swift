import ArgumentParser

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List all VMs and their status"
    )

    func run() throws {
        print("No VMs found.")
    }
}
