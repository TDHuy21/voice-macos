import Foundation
import Observation

@available(macOS 14.2, *)
@Observable
@MainActor
public class TodoStore: @unchecked Sendable {
    #if DEBUG
    public static var shared = TodoStore()
    #else
    public static let shared = TodoStore()
    #endif

    public private(set) var items: [TodoItem] = []
    public private(set) var todayAnchor: Date

    public var onRemainingCountChange: ((Int) -> Void)?
    public var onItemsChanged: (() -> Void)?

    private let repository: TodoRepository
    private let fileStore: FileStoring
    private let fileURL: URL
    private var pendingSave: Task<Void, Never>?

    public init(fileStore: FileStoring = DefaultFileStore(), fileURL: URL = TodoStore.defaultFileURL()) {
        self.fileStore = fileStore
        self.fileURL = fileURL
        self.repository = TodoRepository(fileStore: fileStore, fileURL: fileURL)
        
        let now = Date()
        self.todayAnchor = Calendar.current.startOfDay(for: now)

        // Load synchronously from disk
        var loadedItems = TodoRepository.loadSynchronously(fileStore: fileStore, fileURL: fileURL)
        let originalCount = loadedItems.count
        
        // Prune completed items older than 30 days
        let cutoff = now.addingTimeInterval(-30 * 24 * 3600)
        loadedItems.removeAll { item in
            if case .done(let completedAt) = item.status {
                return completedAt < cutoff
            }
            return false
        }
        
        self.items = loadedItems
        if loadedItems.count != originalCount {
            saveSynchronously()
        }
    }

    public static func defaultFileURL() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("SoundsSource")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        return directory.appendingPathComponent("todos.json")
    }

    public var todaysTasks: [TodoItem] {
        items.filter { item in
            switch item.status {
            case .pending, .blocked:
                return true
            case .done(let t):
                return t >= todayAnchor
            }
        }
    }

    public var remainingCount: Int {
        items.filter { item in
            if case .done = item.status { return false }
            return true
        }.count
    }

    public static func localDayInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86400)
    }

    public func effectiveScheduleToday(_ item: TodoItem) -> TaskSchedule? {
        guard let schedule = item.schedule else { return nil }
        let currentDayInterval = TodoStore.localDayInterval(containing: Date())
        if currentDayInterval.contains(schedule.start) {
            return schedule
        }
        return nil
    }

    public func refreshDayAnchorIfNeeded() {
        let newAnchor = Calendar.current.startOfDay(for: Date())
        if todayAnchor != newAnchor {
            todayAnchor = newAnchor
            onItemsChanged?()
        }
    }

    #if DEBUG
    public func setTodayAnchorForTesting(_ date: Date) {
        todayAnchor = date
    }
    #endif

    public func addTask(title: String, start: Date? = nil, end: Date? = nil) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        print("TodoStore: addTask called with '\(trimmed)'")
        guard !trimmed.isEmpty else { return }
        
        var schedule: TaskSchedule? = nil
        var status: Status = .pending
        
        if let start = start, let end = end {
            schedule = TaskSchedule(start: start, end: end)
            let now = Date()
            if end <= now {
                status = .blocked
            }
        }
        
        let newItem = TodoItem(title: trimmed, status: status, schedule: schedule)
        items.append(newItem)
        print("TodoStore: Successfully appended item, total count: \(items.count)")
        persist()
        onRemainingCountChange?(remainingCount)
        onItemsChanged?()
    }

    public func editTask(id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].title = trimmed
            persist()
            onItemsChanged?()
        }
    }

    public func setSchedule(id: UUID, start: Date, end: Date) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            guard let newSchedule = TaskSchedule(start: start, end: end) else { return }
            items[idx].schedule = newSchedule
            
            let now = Date()
            if end <= now && items[idx].status == .pending {
                items[idx].status = .blocked
            }
            
            persist()
            onItemsChanged?()
            onRemainingCountChange?(remainingCount)
        }
    }

    public func clearSchedule(id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].schedule = nil
            persist()
            onItemsChanged?()
        }
    }

    public func autoBlockOverdueScheduledTasks(now: Date) {
        refreshDayAnchorIfNeeded()
        var changed = false
        for idx in items.indices {
            if items[idx].status == .pending,
               let s = items[idx].schedule,
               s.end <= now {
                items[idx].status = .blocked
                changed = true
            }
        }
        if changed {
            persist()
            onItemsChanged?()
        }
    }

    public func toggleDone(id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            let previousCount = remainingCount
            switch items[idx].status {
            case .done:
                items[idx].status = .pending
            case .pending, .blocked:
                items[idx].status = .done(Date())
            }
            persist()
            onItemsChanged?()
            
            let newCount = remainingCount
            if previousCount != newCount {
                onRemainingCountChange?(newCount)
            }
        }
    }

    public func toggleBlocked(id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            let previousCount = remainingCount
            switch items[idx].status {
            case .blocked:
                items[idx].status = .pending
            case .pending, .done:
                items[idx].status = .blocked
            }
            persist()
            onItemsChanged?()
            
            let newCount = remainingCount
            if previousCount != newCount {
                onRemainingCountChange?(newCount)
            }
        }
    }

    public func deleteTask(id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            let previousCount = remainingCount
            items.remove(at: idx)
            persist()
            onItemsChanged?()
            
            let newCount = remainingCount
            if previousCount != newCount {
                onRemainingCountChange?(newCount)
            }
        }
    }

    public func flush() async {
        await pendingSave?.value
    }

    public func saveSynchronously() {
        let semaphore = DispatchSemaphore(value: 0)
        let previous = pendingSave
        previous?.cancel()
        pendingSave = nil
        
        if let previous {
            Task {
                await previous.value
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 1.0)
        }
        
        let snapshot = items
        do {
            let data = try JSONEncoder().encode(snapshot)
            try fileStore.write(data, to: fileURL)
            print("TodoStore: Synchronously saved \(snapshot.count) todos.")
        } catch {
            print("TodoStore: Failed to save synchronously: \(error)")
        }
    }

    private func persist() {
        let snapshot = items
        let previous = pendingSave
        pendingSave = Task { [repository] in
            await previous?.value
            guard !Task.isCancelled else { return }
            do {
                try await repository.save(snapshot)
                print("TodoStore: Saved \(snapshot.count) todos to disk.")
            } catch {
                print("TodoStore: Failed to save todos: \(error)")
            }
        }
    }
}
