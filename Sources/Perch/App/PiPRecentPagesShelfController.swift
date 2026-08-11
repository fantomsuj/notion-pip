import Combine
import Foundation

struct PiPRecentPageShelfItem: Equatable, Identifiable, Sendable {
    let page: StoredPageSnapshot
    let restoration: DurablePageRestoration?
    let isCurrent: Bool
    let recency: PiPRecentPageRecency

    var id: String { page.pageID }
}

struct PiPRecentPageSelection: Equatable, Sendable {
    let page: NotionPageReference
    let restoration: DurablePageRestoration?
}

enum PiPRecentPageRecency: Equatable, Sendable {
    case current
    case justNow
    case minutes(Int)
    case hours(Int)
    case yesterday
    case weekday(Date)
    case date(Date)

    static func classify(
        visitedAt: Date,
        now: Date,
        calendar: Calendar
    ) -> PiPRecentPageRecency {
        guard visitedAt < now else { return .justNow }

        let visitedDay = calendar.startOfDay(for: visitedAt)
        let currentDay = calendar.startOfDay(for: now)
        let dayDistance = calendar.dateComponents(
            [.day],
            from: visitedDay,
            to: currentDay
        ).day ?? 0

        if dayDistance == 0 {
            let elapsed = now.timeIntervalSince(visitedAt)
            if elapsed < 60 { return .justNow }
            if elapsed < 3_600 { return .minutes(max(Int(elapsed / 60), 1)) }
            return .hours(max(Int(elapsed / 3_600), 1))
        }
        if dayDistance == 1 { return .yesterday }
        if dayDistance > 1, dayDistance < 7 { return .weekday(visitedAt) }
        return .date(visitedAt)
    }

    func label(
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        switch self {
        case .current:
            return "Current"
        case .justNow:
            return "Just now"
        case let .minutes(value):
            return "\(value) min ago"
        case let .hours(value):
            return "\(value) hr ago"
        case .yesterday:
            return "Yesterday"
        case let .weekday(date):
            return formatted(date, template: "EEE", locale: locale, calendar: calendar)
        case let .date(date):
            return formatted(date, template: "MMM d", locale: locale, calendar: calendar)
        }
    }

    private func formatted(
        _ date: Date,
        template: String,
        locale: Locale,
        calendar: Calendar
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

@MainActor
final class PiPRecentPagesShelfController: ObservableObject {
    @Published private(set) var items: [PiPRecentPageShelfItem] = []
    @Published private(set) var isAvailable = false

    private let store: (any PiPRecentPagesProviding)?
    private let clock: any DateProviding
    private let calendarProvider: @MainActor () -> Calendar
    private var loadGeneration = 0

    init(
        store: (any PiPRecentPagesProviding)? = nil,
        clock: any DateProviding = SystemDateProvider(),
        timeZone: TimeZone? = nil,
        calendarProvider: (@MainActor () -> Calendar)? = nil
    ) {
        self.store = store
        self.clock = clock
        if let calendarProvider {
            self.calendarProvider = calendarProvider
        } else if let timeZone {
            self.calendarProvider = {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = timeZone
                return calendar
            }
        } else {
            self.calendarProvider = { Calendar.autoupdatingCurrent }
        }
    }

    func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        guard let store else {
            items = []
            isAvailable = false
            return
        }
        do {
            let snapshot = try await store.recentPiPPages(
                limit: PiPRecentPagesSnapshot.maximumItems
            )
            guard generation == loadGeneration, !Task.isCancelled else { return }
            items = makeItems(snapshot: snapshot, now: clock.now())
            isAvailable = items.count > 1
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            items = []
            isAvailable = false
        }
    }

    func selection(for pageID: String) -> PiPRecentPageSelection? {
        guard let item = items.first(where: {
            $0.page.pageID.caseInsensitiveCompare(pageID) == .orderedSame
        }),
        let page = try? NotionPageReference(validating: item.page.canonicalURL)
        else {
            return nil
        }
        return PiPRecentPageSelection(page: page, restoration: item.restoration)
    }

    private func makeItems(
        snapshot: PiPRecentPagesSnapshot,
        now: Date
    ) -> [PiPRecentPageShelfItem] {
        let calendar = calendarProvider()
        return snapshot.pages.prefix(PiPRecentPagesSnapshot.maximumItems).map { page in
            let isCurrent = page.pageID.caseInsensitiveCompare(
                snapshot.activePageID ?? ""
            ) == .orderedSame
            return PiPRecentPageShelfItem(
                page: page,
                restoration: snapshot.restoration(for: page.pageID),
                isCurrent: isCurrent,
                recency: isCurrent
                    ? .current
                    : PiPRecentPageRecency.classify(
                        visitedAt: page.timestamp,
                        now: now,
                        calendar: calendar
                    )
            )
        }
    }
}
