import ArgumentParser

struct Completions: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate shell completion script"
    )

    @Argument(help: "Shell type (zsh, bash, fish)")
    var shell: String

    func run() throws {
        guard let completionShell = CompletionShell(rawValue: shell) else {
            throw ValidationError("Unsupported shell: \(shell). Use zsh, bash, or fish.")
        }
        let script = Virt.completionScript(for: completionShell)
        print(script)
    }
}
