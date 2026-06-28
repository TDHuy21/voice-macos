import Testing
import Foundation
import AVFoundation
@testable import Engine
@testable import Core

@MainActor
@Suite struct AdversarialEngineTests {
    let url = URL(fileURLWithPath: "/virtual/todos.json")

    private func makeStore(seed: [TodoItem]? = nil) throws -> (TodoStore, InMemoryFileStore) {
        let fs = InMemoryFileStore()
        if let seed { fs.files[url] = try JSONEncoder().encode(seed) }
        return (TodoStore(fileStore: fs, fileURL: url), fs)
    }

    // MARK: - Gap 1: AppAudioNode direct read buffer mismatch
    @Test func appAudioNodeMismatchedBuffersDirectRead() throws {
        let sampleRate: Double = 48000.0
        let engineFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let sourceASBD = engineFormat.streamDescription.pointee
        
        let ringBuffer = RingBuffer(capacity: 64 * 1024)
        
        // Initialize AppAudioNode with ONLY 1 ring buffer, but the format expects 2!
        let appNode = AppAudioNode(ringBuffers: [ringBuffer], sourceFormat: sourceASBD, engineFormat: engineFormat)
        #expect(appNode == nil)
    }

    // MARK: - Gap 2: AppAudioNode converter scratch memory overwrite
    @Test func appAudioNodeConverterScratchOverwrite() throws {
        let tapRate: Double = 44100.0
        let engineRate: Double = 48000.0
        
        let tapFormat = AVAudioFormat(standardFormatWithSampleRate: tapRate, channels: 2)!
        let engineFormat = AVAudioFormat(standardFormatWithSampleRate: engineRate, channels: 2)!
        let sourceASBD = tapFormat.streamDescription.pointee
        
        let ringBuffer = RingBuffer(capacity: 64 * 1024)
        
        // Initialize AppAudioNode with ONLY 1 ring buffer, but format is 2 channels.
        // It needs a converter due to sample rate difference.
        let appNode = AppAudioNode(ringBuffers: [ringBuffer], sourceFormat: sourceASBD, engineFormat: engineFormat)
        #expect(appNode == nil)
    }

    // MARK: - Gap 3: TodoStore pruning on load persistence gap
    @Test func todoStorePruningOnLoadPersistenceGap() throws {
        let fs = InMemoryFileStore()
        let now = Date()
        
        // Seed 3 items: 1 is old completed (should be pruned), 1 is recent completed, 1 is pending
        let oldCompleted = TodoItem(
            title: "Old Completed",
            createdAt: now.addingTimeInterval(-40 * 24 * 3600),
            status: .done(now.addingTimeInterval(-35 * 24 * 3600))
        )
        let oldIncomplete = TodoItem(
            title: "Old Incomplete",
            createdAt: now.addingTimeInterval(-40 * 24 * 3600),
            status: .pending
        )
        let recentCompleted = TodoItem(
            title: "Recent Completed",
            createdAt: now.addingTimeInterval(-5 * 24 * 3600),
            status: .done(now.addingTimeInterval(-4 * 24 * 3600))
        )
        
        let seed = [oldCompleted, oldIncomplete, recentCompleted]
        fs.files[url] = try JSONEncoder().encode(seed)
        
        // Initialize TodoStore
        let store = TodoStore(fileStore: fs, fileURL: url)
        
        // Verify in-memory state: "Old Completed" is pruned, so only 2 items remain
        #expect(store.items.count == 2)
        #expect(!store.items.contains { $0.title == "Old Completed" })
        
        // Verify on-disk state: the file has been written back to disk immediately!
        let data = try #require(fs.files[url])
        let persisted = try JSONDecoder().decode([TodoItem].self, from: data)
        #expect(persisted.count == 2)
        #expect(!persisted.contains { $0.title == "Old Completed" })
        
        print("Adversarial (TodoStore Pruning): verified that disk state is updated with pruned memory state immediately.")
    }

    // MARK: - Gap 4: TodoStore concurrent save race condition / regression
    @Test func todoStoreSaveRaceCondition() async throws {
        let (store, fs) = try makeStore()
        
        // Add a task, triggering async persist()
        store.addTask(title: "Async Task")
        
        // Wait for the first async task to complete
        await store.flush()
        #expect(fs.writeCount == 1)
        
        // Add another task and save synchronously
        store.addTask(title: "Sync Task")
        
        // Save synchronously: disk should now contain ["Async Task", "Sync Task"]
        store.saveSynchronously()
        let midData = try #require(fs.files[url])
        let midPersisted = try JSONDecoder().decode([TodoItem].self, from: midData)
        #expect(midPersisted.count == 2)
        
        // Wait for all async tasks to complete
        await store.flush()
        
        // Verify what is stored in the file store
        let data = try #require(fs.files[url])
        let persisted = try JSONDecoder().decode([TodoItem].self, from: data)
        
        // The first async persist() run after saveSynchronously() should be cancelled.
        // We verify that the writeCount on the mock file store is 2 (1 sync, 1 async),
        // showing that the redundant write was skipped.
        #expect(fs.writeCount == 2)
        #expect(persisted.count == 2)
        #expect(persisted.map(\.title).contains("Sync Task"))
        
        print("Adversarial (TodoStore Race): writeCount = \(fs.writeCount), final count = \(persisted.count)")
    }
}
