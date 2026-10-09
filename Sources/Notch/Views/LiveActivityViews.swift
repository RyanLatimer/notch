import SwiftUI

/// Album art on the left of the camera, a visualizer on the right.
struct MusicActivityView: View {
    let notchSize: CGSize
    @ObservedObject var media = MediaManager.shared
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        let side = NotchViewModel.musicSideWidth
        let art = min(notchSize.height - 10, 22)

        HStack(spacing: 0) {
            ArtworkView(image: media.artwork, size: art, cornerRadius: 5)
                .frame(width: side, alignment: .center)
            Spacer(minLength: notchSize.width)
            AudioVisualizer(
                isPlaying: media.isPlaying,
                color: settings.artworkTintedVisualizer ? Color(nsColor: media.accentColor) : .white
            )
            .frame(width: side, alignment: .center)
        }
        .frame(height: notchSize.height)
    }
}

struct TransientActivityView: View {
    let activity: TransientActivity
    let notchSize: CGSize
    @ObservedObject var battery = BatteryMonitor.shared

    var body: some View {
        let side = activity.sideWidth

        HStack(spacing: 0) {
            leading
                .frame(width: side, alignment: .center)
            Spacer(minLength: notchSize.width)
            trailing
                .frame(width: side, alignment: .center)
        }
        .frame(height: notchSize.height)
    }

    @ViewBuilder
    private var leading: some View {
        switch activity {
        case .charging:
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.green)
                Text("Charging")
                    .foregroundColor(.white)
            }
            .font(.system(size: 11, weight: .semibold))
        case .hud(let event):
            Image(systemName: event.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 20)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch activity {
        case .charging:
            HStack(spacing: 4) {
                Text("\(battery.level)%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white)
                BatteryGlyph(level: battery.level, charging: true)
            }
        case .hud(let event):
            LevelBar(value: event.muted ? 0 : Double(event.value))
                .frame(width: 52, height: 6)
        }
    }
}

struct LevelBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(Color.white)
                    .frame(width: geo.size.width * CGFloat(min(1, max(0, value))))
            }
        }
        .animation(.easeOut(duration: 0.12), value: value)
    }
}

struct BatteryGlyph: View {
    let level: Int
    let charging: Bool

    var body: some View {
        let color: Color = charging ? .green : (level <= 20 ? .red : .white)
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                .frame(width: 22, height: 11)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: max(2, 18 * CGFloat(level) / 100), height: 7)
                .padding(.leading, 2)
        }
        .overlay(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.5))
                .frame(width: 1.5, height: 4)
                .offset(x: 2.5)
        }
    }
}

/// Animated equalizer bars. macOS doesn't expose the output signal without screen-recording
/// permission, so like other notch apps this is a stylised animation while audio plays.
struct AudioVisualizer: View {
    let isPlaying: Bool
    let color: Color
    var barCount = 4
    var maxHeight: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: barHeight(index: index, time: t))
                }
            }
            .frame(height: maxHeight)
        }
    }

    private func barHeight(index: Int, time: Double) -> CGFloat {
        guard isPlaying else { return 3 }
        let i = Double(index)
        let a = sin(time * (5.1 + i * 1.3) + i * 1.7)
        let b = sin(time * (8.3 - i * 0.9) + i * 0.6)
        let c = sin(time * (2.2 + i * 0.4))
        let level = 0.5 + 0.22 * a + 0.18 * b + 0.1 * c
        return max(3, maxHeight * CGFloat(min(1, max(0.15, level))))
    }
}
