import XCTest
import Foundation
@testable import Engine

final class PresetRepositoryTests: XCTestCase {
    let url = URL(fileURLWithPath: "/virtual/presets.json")

    func testRoundTrip() async throws {
        let store = InMemoryFileStore()
        let repo = PresetRepository(fileStore: store, fileURL: url)

        let presets = [
            Preset(name: "Flat", isDefault: true, appSettings: [:]),
            Preset(name: "Bass", isDefault: false, appSettings: ["com.spotify.client": .flat])
        ]
        try await repo.save(presets)
        let loaded = await repo.load()

        XCTAssertEqual(loaded, presets)
    }

    func testLoadMissing() async {
        let repo = PresetRepository(fileStore: InMemoryFileStore(), fileURL: url)
        let loaded = await repo.load()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testLoadCorrupt() async {
        let store = InMemoryFileStore(seed: [url: Data("not json".utf8)])
        let repo = PresetRepository(fileStore: store, fileURL: url)
        let loaded = await repo.load()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testSaveError() async {
        let store = InMemoryFileStore()
        store.writeError = CocoaError(.fileWriteNoPermission)
        let repo = PresetRepository(fileStore: store, fileURL: url)

        do {
            try await repo.save([Preset(name: "Flat", isDefault: true, appSettings: [:])])
            XCTFail("Expected error")
        } catch {
            // Expected
        }
    }

    func testSyncLoad() throws {
        let store = InMemoryFileStore()
        let presets = [Preset(name: "Flat", isDefault: true, appSettings: [:])]
        store.files[url] = try JSONEncoder().encode(presets)

        let loaded = PresetRepository.loadSynchronously(fileStore: store, fileURL: url)
        XCTAssertEqual(loaded, presets)
    }
}
