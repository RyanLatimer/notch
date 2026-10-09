import SwiftUI

struct CalendarWidget: View {
    @ObservedObject var calendar = CalendarService.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(context.date, format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(context.date, format: .dateTime.weekday(.wide))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
                WeekStrip(today: context.date)
                events
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var events: some View {
        if calendar.isAuthorized {
            if calendar.upcoming.isEmpty {
                Text("No upcoming events")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(calendar.upcoming.prefix(2)) { event in
                        EventRow(event: event)
                    }
                }
            }
        } else if calendar.isDenied {
            Text("Calendar access denied in System Settings")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(2)
        } else {
            Button {
                calendar.requestAccess()
            } label: {
                Label("Show events", systemImage: "calendar.badge.plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
    }
}

struct WeekStrip: View {
    let today: Date

    var body: some View {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }

        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let isToday = cal.isDate(day, inSameDayAs: today)
                VStack(spacing: 2) {
                    Text(day, format: .dateTime.weekday(.narrow))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                    Text("\(cal.component(.day, from: day))")
                        .font(.system(size: 10, weight: isToday ? .bold : .medium).monospacedDigit())
                        .foregroundColor(isToday ? .black : .white.opacity(0.8))
                        .frame(width: 19, height: 19)
                        .background(Circle().fill(isToday ? Color.white : Color.clear))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct EventRow: View {
    let event: CalendarEventItem

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(nsColor: event.color))
                .frame(width: 3, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(event.timeDescription)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }
}
