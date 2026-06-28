import Testing
import Foundation
@testable import Engine

@MainActor
@Suite struct TodoSchedulerTests {
    let url = URL(fileURLWithPath: "/virtual/todos.json")

    init() {
        TodoScheduler.skipNotificationCenter = true
    }

    private func makeStore(seed: [TodoItem]? = nil) throws -> (TodoStore, InMemoryFileStore) {
        let fs = InMemoryFileStore()
        if let seed { fs.files[url] = try JSONEncoder().encode(seed) }
        return (TodoStore(fileStore: fs, fileURL: url), fs)
    }

    @Test func taskScheduleValidation() throws {
        let now = Date()
        let start = now
        let end = now.addingTimeInterval(3600)
        
        // Valid same day end > start
        let valid = TaskSchedule(start: start, end: end)
        #expect(valid != nil)
        
        // Invalid end <= start
        let invalidEnd = TaskSchedule(start: start, end: start.addingTimeInterval(-10))
        #expect(invalidEnd == nil)
        
        // Invalid midnight-straddling (different days)
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = todayStart.appending(days: 1)
        
        let invalidDay = TaskSchedule(start: todayStart.addingTimeInterval(23 * 3600), end: tomorrowStart.addingTimeInterval(3600))
        #expect(invalidDay == nil)
    }

    @Test func addTaskWithSchedule() throws {
        let (store, _) = try makeStore()
        let now = Date()
        let start = now.addingTimeInterval(3600)
        let end = now.addingTimeInterval(7200)
        
        store.addTask(title: "Task with schedule", start: start, end: end)
        
        #expect(store.items.count == 1)
        #expect(store.items[0].title == "Task with schedule")
        #expect(store.items[0].status == .pending)
        #expect(store.items[0].schedule?.start == start)
        #expect(store.items[0].schedule?.end == end)
    }

    @Test func addTaskPastWindowAutoBlocks() throws {
        let (store, _) = try makeStore()
        let now = Date()
        let start = now.addingTimeInterval(-3600)
        let end = now.addingTimeInterval(-1800) // 30 minutes in the past
        
        store.addTask(title: "Overdue task", start: start, end: end)
        
        #expect(store.items.count == 1)
        #expect(store.items[0].title == "Overdue task")
        #expect(store.items[0].status == .blocked)
        #expect(store.items[0].schedule?.start == start)
        #expect(store.items[0].schedule?.end == end)
    }

    @Test func setSchedulePastWindowAutoBlocks() throws {
        let (store, _) = try makeStore()
        store.addTask(title: "Task 1")
        let id = store.items[0].id
        
        let now = Date()
        let start = now.addingTimeInterval(-3600)
        let end = now.addingTimeInterval(-1800) // 30 minutes in the past
        
        store.setSchedule(id: id, start: start, end: end)
        
        #expect(store.items[0].status == .blocked)
        #expect(store.remainingCount == 1) // Blocked tasks are still remaining
    }

    @Test func autoBlockOverdueScheduledTasks() throws {
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        
        let overdue = TodoItem(
            title: "Overdue",
            createdAt: todayStart,
            status: .pending,
            schedule: TaskSchedule(start: todayStart, end: now.addingTimeInterval(-10))
        )
        let active = TodoItem(
            title: "Active",
            createdAt: todayStart,
            status: .pending,
            schedule: TaskSchedule(start: todayStart, end: now.addingTimeInterval(3600))
        )
        let doneOverdue = TodoItem(
            title: "Done Overdue",
            createdAt: todayStart,
            status: .done(now),
            schedule: TaskSchedule(start: todayStart, end: now.addingTimeInterval(-10))
        )
        
        let (store, _) = try makeStore(seed: [overdue, active, doneOverdue])
        
        store.autoBlockOverdueScheduledTasks(now: now)
        
        #expect(store.items[0].status == .blocked) // Overdue pending task blocked
        #expect(store.items[1].status == .pending) // Active remains pending
        #expect(store.items[2].isDone)           // Done remains done
    }

    @Test func midnightRolloverAutoBlocking() throws {
        // Save original shared TodoStore
        let originalSharedStore = TodoStore.shared
        defer { TodoStore.shared = originalSharedStore }
        
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let yesterday = todayStart.appending(days: -1)
        let yesterdayStart = calendar.startOfDay(for: yesterday)
        let yesterdayEnd = yesterdayStart.addingTimeInterval(3600)
        
        // 1. Add a pending task scheduled on yesterday
        let yesterdayTask = TodoItem(
            title: "Yesterday Pending Task",
            createdAt: yesterdayStart,
            status: .pending,
            schedule: TaskSchedule(start: yesterdayStart, end: yesterdayEnd)
        )
        
        let (mockStore, _) = try makeStore(seed: [yesterdayTask])
        TodoStore.shared = mockStore
        
        // 2. Set todayAnchor to yesterday (simulating we are still on yesterday)
        mockStore.setTodayAnchorForTesting(yesterdayStart)
        
        // 3. Call sweep() which will refresh day anchor and trigger autoBlock
        // since current time Date() is "today", it will rollover the day and sweep.
        TodoScheduler.shared.sweep()
        
        // 4. Verify that the task is auto-blocked and todayAnchor rolled over to today
        #expect(mockStore.items[0].status == .blocked)
        #expect(mockStore.todayAnchor == todayStart)
    }

    @Test func deinitCleansUpNotificationObservers() throws {
        weak var weakScheduler: TodoScheduler?
        do {
            let scheduler = TodoScheduler()
            weakScheduler = scheduler
            #expect(weakScheduler != nil)
        }
        
        // Verify deallocation
        #expect(weakScheduler == nil)
        
        // Posting notifications should not crash the app after cleanup
        NotificationCenter.default.post(name: Notification.Name.NSSystemClockDidChange, object: nil)
        NotificationCenter.default.post(name: Notification.Name.NSSystemTimeZoneDidChange, object: nil)
        NotificationCenter.default.post(name: Notification.Name.NSCalendarDayChanged, object: nil)
    }
}

fileprivate extension Date {
    func appending(days: Int) -> Date {
        return Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }
}
