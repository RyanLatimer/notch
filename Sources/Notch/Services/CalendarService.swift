import AppKit
import Combine
import EventKit

struct CalendarEventItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: NSColor

    var timeDescription: String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(start) {
            day = ""
        } else if calendar.isDateInTomorrow(start) {
            day = "Tomorrow "
        } else {
            day = start.formatted(.dateTime.weekday(.abbreviated)) + " "
        }
        if isAllDay { return day.isEmpty ? "All day" : day + "· all day" }
        if start <= Date() && end > Date() {
            return "Now · until " + end.formatted(date: .omitted, time: .shortened)
        }
        return day + start.formatted(date: .omitted, time: .shortened)
    }
}

final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    @Published private(set) var upcoming: [CalendarEventItem] = []
    @Published private(set) var isAuthorized = false
    @Published private(set) var isDenied = false

    private let store = EKEventStore()
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func start() {
        updateAuthorization()
        reload()

        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .merge(with: NotificationCenter.default.publisher(for: .NSCalendarDayChanged))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)

        // Moves "now" forward so finished events drop off.
        Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    private func updateAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            isAuthorized = status == .fullAccess
        } else {
            isAuthorized = status == .authorized
        }
        isDenied = status == .denied || status == .restricted
    }

    func requestAccess() {
        NSApp.activate(ignoringOtherApps: true)
        let completion: (Bool, Error?) -> Void = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateAuthorization()
                self?.reload()
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: completion)
        } else {
            store.requestAccess(to: .event, completion: completion)
        }
    }

    func reload() {
        guard isAuthorized else {
            upcoming = []
            return
        }
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: now)) else { return }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return !lhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
            .prefix(6)
            .map { event in
                CalendarEventItem(
                    id: (event.eventIdentifier ?? UUID().uuidString) + "\(event.startDate.timeIntervalSince1970)",
                    title: event.title ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    color: event.calendar?.color ?? .systemBlue
                )
            }
        upcoming = Array(events)
    }
}
