import ArgumentParser

@main
struct Virt: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "virt",
        abstract: "Manage Linux VMs on macOS using Virtualization.framework",
        subcommands: [
            Create.self,
            Start.self,
            Stop.self,
            Delete.self,
            List.self,
        ]
    )
}
