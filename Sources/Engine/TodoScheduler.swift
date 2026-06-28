import Foundation
@preconcurrency import UserNotifications
import AppKit
import Observation

@available(macOS 14.2, *)
@MainActor
@Observable
public final class TodoScheduler: NSObject, @unchecked Sendable {
    public static let shared = TodoScheduler()
    #if DEBUG
    public static var skipNotificationCenter = false
    #endif
    
    public var showDeniedPermissionCue = false {
        didSet {
            TodoStore.shared.onRemainingCountChange?(TodoStore.shared.remainingCount)
        }
    }
    
    private var timer: DispatchSourceTimer?
    private var deliveredActiveCues = Set<UUID>()
    private var midnightTimer: DispatchSourceTimer?
    private var isRecomputing = false
    private var syncTask: Task<Void, Never>?
    
    #if DEBUG
    override init() {
        super.init()
    }
    #else
    private override init() {
        super.init()
    }
    #endif

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    
    public func start() {
        UNUserNotificationCenter.current().delegate = self
        setupObservers()
        recompute()
        sweep()
    }
    
    private func setupObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleClockOrDayChange), name: Notification.Name.NSSystemClockDidChange, object: nil)
        nc.addObserver(self, selector: #selector(handleClockOrDayChange), name: Notification.Name.NSSystemTimeZoneDidChange, object: nil)
        nc.addObserver(self, selector: #selector(handleClockOrDayChange), name: Notification.Name.NSCalendarDayChanged, object: nil)
        
        let wsNc = NSWorkspace.shared.notificationCenter
        wsNc.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        
        TodoStore.shared.onItemsChanged = { [weak self] in
            Task { @MainActor [weak self] in
                self?.recompute()
            }
        }
    }
    
    @objc @MainActor private func handleClockOrDayChange() {
        TodoStore.shared.refreshDayAnchorIfNeeded()
        recompute()
        sweep()
    }
    
    @objc @MainActor private func handleWake() {
        TodoStore.shared.refreshDayAnchorIfNeeded()
        recompute()
        sweep()
    }
    
    @MainActor private func handleMidnight() {
        TodoStore.shared.refreshDayAnchorIfNeeded()
        recompute()
        sweep()
    }
    
    private func scheduleMidnightTimer() {
        midnightTimer?.cancel()
        
        let calendar = Calendar.current
        let now = Date()
        guard let nextMidnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else { return }
        
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let delay = nextMidnight.timeIntervalSince(now)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleMidnight()
            }
        }
        timer.resume()
        self.midnightTimer = timer
    }
    
    private func scheduleNextEndTimer(deadlines: [Date]) {
        timer?.cancel()
        timer = nil
        
        let now = Date()
        let futureDeadlines = deadlines.filter { $0 > now }.sorted()
        guard let nextDeadline = futureDeadlines.first else { return }
        
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let delay = nextDeadline.timeIntervalSince(now)
        timer.schedule(deadline: .now() + delay + 0.1)
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.sweep()
            }
        }
        timer.resume()
        self.timer = timer
    }
    
    @MainActor
    public func sweep() {
        let now = Date()
        TodoStore.shared.autoBlockOverdueScheduledTasks(now: now)
        recompute()
    }
    
    @MainActor
    public func recompute() {
        guard !isRecomputing else { return }
        isRecomputing = true
        defer { isRecomputing = false }
        
        let store = TodoStore.shared
        store.refreshDayAnchorIfNeeded()
        scheduleMidnightTimer()
        
        let now = Date()
        let todayTasks = store.items
        
        var endTimes = [Date]()
        var futureStarts = [TodoItem]()
        var activeTasks = [TodoItem]()
        
        for item in todayTasks {
            if let s = store.effectiveScheduleToday(item) {
                if item.status == .pending {
                    endTimes.append(s.end)
                    if s.start > now {
                        futureStarts.append(item)
                    } else if now < s.end {
                        activeTasks.append(item)
                    }
                }
            }
        }
        
        scheduleNextEndTimer(deadlines: endTimes)
        
        for task in activeTasks {
            if !deliveredActiveCues.contains(task.id) {
                deliveredActiveCues.insert(task.id)
                Task {
                    await fireActiveNowCue(for: task)
                }
            }
        }
        
        let activeTaskIds = Set(activeTasks.map(\.id))
        deliveredActiveCues.formIntersection(activeTaskIds)
        
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            guard let self = self else { return }
            await self.syncStartNotifications(for: futureStarts)
        }
    }
    
    @MainActor
    private func fireActiveNowCue(for task: TodoItem) async {
        #if DEBUG
        if TodoScheduler.skipNotificationCenter { return }
        #endif
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized {
            let content = UNMutableNotificationContent()
            content.title = "Đến giờ thực hiện"
            content.body = task.title
            content.sound = UNNotificationSound.default
            
            let request = UNNotificationRequest(
                identifier: "todo-start-\(task.id)",
                content: content,
                trigger: nil
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                print("TodoScheduler: failed to add active now cue: \(error)")
            }
        } else {
            NSSound(named: "Glass")?.play()
            self.showDeniedPermissionCue = true
        }
    }
    
    @MainActor
    public func requestAuthorizationIfNeeded() async {
        #if DEBUG
        if TodoScheduler.skipNotificationCenter { return }
        #endif
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                print("TodoScheduler: notification auth request failed: \(error)")
            }
        }
    }
    
    @MainActor
    private func syncStartNotifications(for futureStarts: [TodoItem]) async {
        #if DEBUG
        if TodoScheduler.skipNotificationCenter { return }
        #endif
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        if Task.isCancelled { return }
        let existingIds = Set(requests.compactMap { request -> UUID? in
            guard request.identifier.hasPrefix("todo-start-") else { return nil }
            let idStr = request.identifier.dropFirst("todo-start-".count)
            return UUID(uuidString: String(idStr))
        })
        
        let targetIds = Set(futureStarts.map(\.id))
        
        let toRemove = existingIds.subtracting(targetIds).map { "todo-start-\($0)" }
        if !toRemove.isEmpty {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: toRemove)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: toRemove)
        }
        
        for item in futureStarts {
            if Task.isCancelled { return }
            guard let s = TodoStore.shared.effectiveScheduleToday(item) else { continue }
            
            let content = UNMutableNotificationContent()
            content.title = "Đến giờ thực hiện"
            content.body = item.title
            content.sound = UNNotificationSound.default
            
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: s.start)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
            let request = UNNotificationRequest(
                identifier: "todo-start-\(item.id)",
                content: content,
                trigger: trigger
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                print("TodoScheduler: failed to add notification: \(error)")
            }
        }
    }
    
    @MainActor
    public func cancelNotifications(for id: UUID) {
        #if DEBUG
        if TodoScheduler.skipNotificationCenter { return }
        #endif
        let idStr = "todo-start-\(id)"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [idStr])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [idStr])
    }
}

@available(macOS 14.2, *)
@MainActor
extension TodoScheduler: @preconcurrency UNUserNotificationCenterDelegate {
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let identifier = notification.request.identifier
        if identifier.hasPrefix("todo-start-") {
            let idStr = String(identifier.dropFirst("todo-start-".count))
            if let id = UUID(uuidString: idStr) {
                let store = TodoStore.shared
                if let item = store.items.first(where: { $0.id == id }),
                   item.status == .pending,
                   let s = store.effectiveScheduleToday(item),
                   s.start <= Date() {
                    completionHandler([.banner, .sound])
                    return
                }
            }
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound])
    }
}
