import XCTest
@testable import virt

final class VMConfigTests: XCTestCase {
    func testRoundTrip() throws {
        let config = VMConfig(name: "test", cpus: 4, memoryMB: 2048, diskSizeGB: 20)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = tempDir.appendingPathComponent("config.json")
        try config.write(to: url)
        let loaded = try VMConfig.load(from: url)

        XCTAssertEqual(loaded.name, "test")
        XCTAssertEqual(loaded.cpus, 4)
        XCTAssertEqual(loaded.memoryMB, 2048)
        XCTAssertEqual(loaded.diskSizeGB, 20)
    }

    func testJSONIsPrettyPrinted() throws {
        let config = VMConfig(name: "vm1", cpus: 1, memoryMB: 512, diskSizeGB: 5)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = tempDir.appendingPathComponent("config.json")
        try config.write(to: url)
        let json = try String(contentsOf: url, encoding: .utf8)

        // Pretty printed JSON contains newlines
        XCTAssertTrue(json.contains("\n"))
        // Sorted keys means cpus comes before name
        let cpusRange = json.range(of: "cpus")!
        let nameRange = json.range(of: "name")!
        XCTAssertTrue(cpusRange.lowerBound < nameRange.lowerBound)
    }

    func testLoadCorruptFileThrows() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = tempDir.appendingPathComponent("config.json")
        try "not json".write(to: url, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try VMConfig.load(from: url))
    }
}
