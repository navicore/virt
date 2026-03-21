import XCTest
@testable import virt

final class VMDirectoryTests: XCTestCase {
    func testPathConstruction() {
        let dir = VMDirectory(name: "myvm")
        XCTAssertTrue(dir.rootURL.path.hasSuffix(".virt/vms/myvm"))
        XCTAssertTrue(dir.configURL.path.hasSuffix("myvm/config.json"))
        XCTAssertTrue(dir.diskURL.path.hasSuffix("myvm/disk.raw"))
        XCTAssertTrue(dir.nvramURL.path.hasSuffix("myvm/nvram.bin"))
        XCTAssertTrue(dir.pidURL.path.hasSuffix("myvm/vm.pid"))
    }

    func testExistsReturnsFalseForMissing() {
        let dir = VMDirectory(name: "nonexistent-\(UUID().uuidString)")
        XCTAssertFalse(dir.exists)
    }

    func testCreateAndRemove() throws {
        let name = "test-\(UUID().uuidString)"
        let dir = VMDirectory(name: name)
        defer { try? dir.remove() }

        XCTAssertFalse(dir.exists)
        try dir.create()
        XCTAssertTrue(dir.exists)
        try dir.remove()
        XCTAssertFalse(dir.exists)
    }
}
