import XCTest
import Foundation
@testable import Engine

@MainActor
final class PresetStoreTests: XCTestCase {
    let url = URL(fileURLWithPath: "/virtual/presets.json")

    /// Fresh store backed by an in-memory file store (no disk, no shared singleton).
    private func makeStore(seed: [Preset]? = nil) throws -> (PresetStore, InMemoryFileStore) {
        let fs = InMemoryFileStore()
        if let seed { fs.files[url] = try JSONEncoder().encode(seed) }
        return (PresetStore(fileStore: fs, fileURL: url), fs)
    }

    func testSeedsFlat() throws {
        let (store, _) = try makeStore()
        XCTAssertEqual(store.presets.count, 1)
        XCTAssertEqual(store.defaultPreset?.name, "Flat")
    }

    func testSaveAppends() throws {
        let (store, _) = try makeStore(seed: [Preset(name: "Flat", isDefault: true, appSettings: [:])])
        store.savePreset(name: "Bass", appSettings: ["com.app": .flat])
        XCTAssertEqual(store.presets.map(\.name), ["Flat", "Bass"])
    }

    func testSaveUpdates() throws {
        let (store, _) = try makeStore(seed: [Preset(name: "Flat", isDefault: true, appSettings: [:])])
        store.savePreset(name: "Flat", appSettings: ["com.app": .flat])
        XCTAssertEqual(store.presets.count, 1)
        XCTAssertEqual(store.presets[0].appSettings["com.app"], .flat)
    }

    func testDeleteReassignsDefault() throws {
        let (store, _) = try makeStore(seed: [
            Preset(name: "Flat", isDefault: true, appSettings: [:]),
            Preset(name: "Bass", isDefault: false, appSettings: [:])
        ])
        store.deletePreset(name: "Flat")
        XCTAssertEqual(store.presets.count, 1)
        XCTAssertEqual(store.defaultPreset?.name, "Bass")
    }

    func testRename() throws {
        let (store, _) = try makeStore(seed: [Preset(name: "Flat", isDefault: true, appSettings: [:])])
        store.renamePreset(oldName: "Flat", newName: "Neutral")
        XCTAssertEqual(store.defaultPreset?.name, "Neutral")

        store.renamePreset(oldName: "Neutral", newName: "")
        XCTAssertEqual(store.presets[0].name, "Neutral") // unchanged
    }

    func testSetDefault() throws {
        let (store, _) = try makeStore(seed: [
            Preset(name: "Flat", isDefault: true, appSettings: [:]),
            Preset(name: "Bass", isDefault: false, appSettings: [:])
        ])
        store.setDefaultPreset(name: "Bass")
        XCTAssertEqual(store.defaultPreset?.name, "Bass")
        XCTAssertEqual(store.presets.filter(\.isDefault).count, 1)
    }

    func testPersistsToDisk() async throws {
        let (store, fs) = try makeStore(seed: [Preset(name: "Flat", isDefault: true, appSettings: [:])])
        store.savePreset(name: "Bass", appSettings: [:])
        await store.flush() // wait for the off-main-thread write

        let data = try XCTUnwrap(fs.files[url])
        let persisted = try JSONDecoder().decode([Preset].self, from: data)
        XCTAssertEqual(persisted.map(\.name), ["Flat", "Bass"])
    }
}
