import ArgumentParser
import Foundation

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List all VMs and their status"
    )

    func run() throws {
        let vms = try VMDirectory.allVMs()

        guard !vms.isEmpty else {
            print("No VMs found.")
            return
        }

        let nameWidth = max(vms.map(\.name.count).max() ?? 4, 4)

        print("\("NAME".padding(toLength: nameWidth, withPad: " ", startingAt: 0))  CPUS   MEMORY  STATUS")
        print(String(repeating: "-", count: nameWidth + 35))

        for dir in vms.sorted(by: { $0.name < $1.name }) {
            guard FileManager.default.fileExists(atPath: dir.configURL.path) else {
                continue
            }

            let config = try VMConfig.load(from: dir.configURL)
            let status = vmStatus(dir: dir)
            let namePadded = config.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)

            print("\(namePadded)  \(String(config.cpus).padding(toLength: 4, withPad: " ", startingAt: 0))  \(String(config.memoryMB).padding(toLength: 5, withPad: " ", startingAt: 0)) MB  \(status)")
        }
    }

    private func vmStatus(dir: VMDirectory) -> String {
        guard FileManager.default.fileExists(atPath: dir.pidURL.path),
              let pidString = try? String(contentsOf: dir.pidURL, encoding: .utf8)
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidString),
              kill(pid, 0) == 0 else {
            return "stopped"
        }
        return "running (PID \(pid))"
    }
}
