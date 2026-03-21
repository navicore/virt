import Foundation

struct VMConfig: Codable {
    let name: String
    let cpus: Int
    let memoryMB: Int
    let diskSizeGB: Int

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }

    static func load(from url: URL) throws -> VMConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(VMConfig.self, from: data)
    }
}
