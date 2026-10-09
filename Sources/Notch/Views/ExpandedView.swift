import SwiftUI

struct ExpandedView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var shelf = ShelfStore.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            page
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: vm.expandedBodySize.width, height: vm.expandedBodySize.height)
    }

    /// The row level with the camera housing: tabs on the left, status on the right.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                TabButton(tab: .home, selection: $vm.tab)
                if settings.enableShelf {
                    TabButton(tab: .shelf, selection: $vm.tab, badge: shelf.items.count)
                }
            }
            Spacer(minLength: vm.notchSize.width + 16)
            HStack(spacing: 10) {
                BatteryStatusView()
                Button(action: vm.openSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: vm.notchSize.height)
    }

    @ViewBuilder
    private var page: some View {
        switch vm.tab {
        case .home:
            HomeView()
        case .shelf:
            ShelfView(isDropTargeted: vm.isDropTargeted)
        }
    }
}

struct TabButton: View {
    let tab: NotchTab
    @Binding var selection: NotchTab
    var badge: Int = 0

    var body: some View {
        let selected = selection == tab
        Button {
            selection = tab
        } label: {
            Image(systemName: tab.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(selected ? .white : .white.opacity(0.45))
                .frame(width: 30, height: 22)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.16 : 0)))
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 3)
                            .background(Capsule().fill(Color.white))
                            .offset(x: 2, y: -1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct BatteryStatusView: View {
    @ObservedObject var battery = BatteryMonitor.shared

    var body: some View {
        if battery.hasBattery {
            HStack(spacing: 5) {
                Text("\(battery.level)%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.75))
                BatteryGlyph(level: battery.level, charging: battery.isCharging || battery.isPluggedIn)
            }
        }
    }
}

struct HomeView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 16) {
            MediaPlayerView()
                .frame(maxWidth: .infinity, alignment: .leading)
            if settings.showCalendar {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1)
                    .padding(.vertical, 6)
                CalendarWidget()
                    .frame(width: 168)
            }
        }
    }
}
