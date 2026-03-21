import Foundation

struct VMDirectory {
    static let baseURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".virt")
            .appendingPathComponent("vms")
    }()

    let name: String

    var rootURL: URL {
        VMDirectory.baseURL.appendingPathComponent(name)
    }

    var configURL: URL {
        rootURL.appendingPathComponent("config.json")
    }

    var diskURL: URL {
        rootURL.appendingPathComponent("disk.raw")
    }

    var nvramURL: URL {
        rootURL.appendingPathComponent("nvram.bin")
    }

    var pidURL: URL {
        rootURL.appendingPathComponent("vm.pid")
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: rootURL.path)
    }

    func create() throws {
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
    }

    func remove() throws {
        try FileManager.default.removeItem(at: rootURL)
    }

    /// Returns all VM directories under ~/.virt/vms/
    static func allVMs() throws -> [VMDirectory] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: baseURL.path) else { return [] }
        let contents = try fm.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        return contents.compactMap { url in
            let name = url.lastPathComponent
            guard !name.hasPrefix("."),
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                return nil
            }
            return VMDirectory(name: name)
        }
    }
}
