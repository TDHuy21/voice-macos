import Testing
import Foundation
@testable import Engine

@MainActor
@Suite struct TodoStoreTests {
    let url = URL(fileURLWithPath: "/virtual/todos.json")

    private func makeStore(seed: [TodoItem]? = nil) throws -> (TodoStore, InMemoryFileStore) {
        let fs = InMemoryFileStore()
        if let seed { fs.files[url] = try JSONEncoder().encode(seed) }
        return (TodoStore(fileStore: fs, fileURL: url), fs)
    }

    @Test func initialEmpty() throws {
        let (store, _) = try makeStore()
        #expect(store.items.isEmpty)
        #expect(store.todaysTasks.isEmpty)
        #expect(store.remainingCount == 0)
    }

    @Test func addTask() throws {
        let (store, _) = try makeStore()
        store.addTask(title: "Task 1")
        store.addTask(title: "  ") // Should be rejected
        #expect(store.items.count == 1)
        #expect(store.items[0].title == "Task 1")
        #expect(store.remainingCount == 1)
    }

    @Test func editTask() throws {
        let (store, _) = try makeStore()
        store.addTask(title: "Task 1")
        let item = store.items[0]
        store.editTask(id: item.id, title: "Task 1 Edited")
        store.editTask(id: item.id, title: "") // Should be rejected
        #expect(store.items[0].title == "Task 1 Edited")
    }

    @Test func deleteTask() throws {
        let (store, _) = try makeStore()
        store.addTask(title: "Task 1")
        let id = store.items[0].id
        store.deleteTask(id: id)
        #expect(store.items.isEmpty)
    }

    @Test func toggleDone() throws {
        let (store, _) = try makeStore()
        store.addTask(title: "Task 1")
        let id = store.items[0].id
        
        #expect(store.items[0].status == .pending)
        #expect(!store.items[0].isDone)
        #expect(store.remainingCount == 1)

        store.toggleDone(id: id)
        #expect(store.items[0].isDone)
        #expect(store.remainingCount == 0)

        store.toggleDone(id: id)
        #expect(store.items[0].status == .pending)
        #expect(!store.items[0].isDone)
        #expect(store.remainingCount == 1)
    }

    @Test func toggleBlocked() throws {
        let (store, _) = try makeStore()
        store.addTask(title: "Task 1")
        let id = store.items[0].id
        
        #expect(store.items[0].status == .pending)
        #expect(store.remainingCount == 1)

        store.toggleBlocked(id: id)
        #expect(store.items[0].status == .blocked)
        #expect(store.remainingCount == 1)

        store.toggleBlocked(id: id)
        #expect(store.items[0].status == .pending)
        #expect(store.remainingCount == 1)
    }

    @Test func blockedToDone() throws {
        let (store, _) = try makeStore()
        store.addTask(title: "Task 1")
        let id = store.items[0].id
        
        store.toggleBlocked(id: id)
        #expect(store.items[0].status == .blocked)
        #expect(store.remainingCount == 1)

        store.toggleDone(id: id)
        #expect(store.items[0].isDone)
        #expect(store.remainingCount == 0)
    }

    @Test func pruningOnLoad() throws {
        let now = Date()
        let oldCompleted = TodoItem(title: "Old Completed", createdAt: now.addingTimeInterval(-40 * 24 * 3600), status: .done(now.addingTimeInterval(-35 * 24 * 3600)))
        let oldIncomplete = TodoItem(title: "Old Incomplete", createdAt: now.addingTimeInterval(-40 * 24 * 3600), status: .pending)
        let recentCompleted = TodoItem(title: "Recent Completed", createdAt: now.addingTimeInterval(-5 * 24 * 3600), status: .done(now.addingTimeInterval(-4 * 24 * 3600)))

        let seed = [oldCompleted, oldIncomplete, recentCompleted]
        let (store, _) = try makeStore(seed: seed)

        #expect(store.items.count == 2)
        #expect(store.items.contains { $0.title == "Old Incomplete" })
        #expect(store.items.contains { $0.title == "Recent Completed" })
    }

    @Test func carryOverFilter() throws {
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = todayStart.addingTimeInterval(-24 * 3600)

        let unfinished = TodoItem(title: "Unfinished", createdAt: yesterdayStart, status: .pending)
        let completedToday = TodoItem(title: "Completed Today", createdAt: todayStart, status: .done(now))
        let completedYesterday = TodoItem(title: "Completed Yesterday", createdAt: yesterdayStart, status: .done(yesterdayStart.addingTimeInterval(3600)))
        let blockedYesterday = TodoItem(title: "Blocked Yesterday", createdAt: yesterdayStart, status: .blocked)

        // Seed on load instead of mutating items directly
        let (store, _) = try makeStore(seed: [unfinished, completedToday, completedYesterday, blockedYesterday])

        let titles = store.todaysTasks.map(\.title)
        #expect(titles.count == 3)
        #expect(titles.contains("Unfinished"))
        #expect(titles.contains("Completed Today"))
        #expect(titles.contains("Blocked Yesterday"))
        #expect(!titles.contains("Completed Yesterday"))
    }

    @Test func remainingCountChangeHook() throws {
        let (store, _) = try makeStore()
        var countReceived: Int?
        store.onRemainingCountChange = { count in
            countReceived = count
        }

        store.addTask(title: "Task 1")
        #expect(countReceived == 1)

        let id = store.items[0].id
        store.toggleDone(id: id)
        #expect(countReceived == 0)

        store.addTask(title: "Task 2")
        #expect(countReceived == 1)
        store.deleteTask(id: store.items[1].id)
        #expect(countReceived == 0)
    }

    @Test func persistsToDisk() async throws {
        let (store, fs) = try makeStore()
        store.addTask(title: "Task 1")
        await store.flush()

        let data = try #require(fs.files[url])
        let persisted = try JSONDecoder().decode([TodoItem].self, from: data)
        #expect(persisted.count == 1)
        #expect(persisted[0].title == "Task 1")
    }

    @Test func saveSynchronously() throws {
        let (store, fs) = try makeStore()
        store.addTask(title: "Task 1")
        store.saveSynchronously()

        let data = try #require(fs.files[url])
        let persisted = try JSONDecoder().decode([TodoItem].self, from: data)
        #expect(persisted.count == 1)
        #expect(persisted[0].title == "Task 1")
    }
}
