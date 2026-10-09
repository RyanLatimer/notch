import AppKit

struct ShelfItem: Identifiable, Equatable, Codable {
    let id: UUID
    let url: URL
}

/// Files parked in the notch. Stores references, not copies; missing files are pruned on launch.
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()

    @Published private(set) var items: [ShelfItem] = [] {
        didSet { save() }
    }

    private let storageKey = "shelfItems"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([ShelfItem].self, from: data) {
            items = saved.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        }
    }

    func add(_ urls: [URL]) {
        let existing = Set(items.map(\.url))
        let new = urls.filter { !existing.contains($0) }.map { ShelfItem(id: UUID(), url: $0) }
        if !new.isEmpty { items.append(contentsOf: new) }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }

    func airDrop(_ items: [ShelfItem]) {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: items.map(\.url))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
