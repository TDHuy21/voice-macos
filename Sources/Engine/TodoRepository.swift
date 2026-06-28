import Foundation

@available(macOS 14.2, *)
public actor TodoRepository {
    private let fileStore: FileStoring
    private let fileURL: URL

    public init(fileStore: FileStoring = DefaultFileStore(), fileURL: URL) {
        self.fileStore = fileStore
        self.fileURL = fileURL
    }

    public func load() -> [TodoItem] {
        Self.loadSynchronously(fileStore: fileStore, fileURL: fileURL)
    }

    public func save(_ todos: [TodoItem]) throws {
        let data = try JSONEncoder().encode(todos)
        try fileStore.write(data, to: fileURL)
    }

    public nonisolated static func loadSynchronously(fileStore: FileStoring, fileURL: URL) -> [TodoItem] {
        guard fileStore.fileExists(at: fileURL),
              let data = try? fileStore.read(from: fileURL),
              let todos = try? JSONDecoder().decode([TodoItem].self, from: data) else {
            return []
        }
        return todos
    }
}
