import ArgumentParser

@main
struct Virt: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "virt",
        abstract: "Manage Linux VMs on macOS using Virtualization.framework",
        subcommands: [
            Create.self,
            Install.self,
            Start.self,
            Stop.self,
            Delete.self,
            List.self,
            Completions.self,
        ]
    )
}
