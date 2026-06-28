import Foundation

@available(macOS 14.2, *)
public enum Status: Codable, Hashable, Sendable {
    case pending
    case blocked
    case done(Date)
}

@available(macOS 14.2, *)
public struct TaskSchedule: Codable, Hashable, Sendable {
    public let start: Date
    public let end: Date
    
    public init?(start: Date, end: Date, calendar: Calendar = .current) {
        guard end > start, calendar.isDate(start, inSameDayAs: end) else { return nil }
        self.start = start
        self.end = end
    }
    
    public var formattedTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }
}

@available(macOS 14.2, *)
public struct TodoItem: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var status: Status
    public var schedule: TaskSchedule?
    
    public var isDone: Bool {
        if case .done = status { return true }
        return false
    }
    
    public init(id: UUID = UUID(), title: String, createdAt: Date = Date(), status: Status = .pending, schedule: TaskSchedule? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.status = status
        self.schedule = schedule
    }
}
