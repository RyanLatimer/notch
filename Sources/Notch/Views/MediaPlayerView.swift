import SwiftUI

struct MediaPlayerView: View {
    @ObservedObject var media = MediaManager.shared

    var body: some View {
        if let info = media.info {
            player(info)
        } else {
            emptyState
        }
    }

    private func player(_ info: NowPlayingInfo) -> some View {
        HStack(spacing: 14) {
            ArtworkView(image: media.artwork, size: 92, cornerRadius: 14, badge: media.appIcon)
                .shadow(color: Color(nsColor: media.accentColor).opacity(0.35), radius: 12)
                .onTapGesture { media.openPlayerApp() }
                .help("Open \(media.appName ?? "player")")

            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(info.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)

                Spacer(minLength: 4)

                ProgressScrubber(
                    info: info,
                    accent: Color(nsColor: media.accentColor),
                    onSeek: { media.seek(to: $0) }
                )

                HStack(spacing: 18) {
                    ControlButton(symbol: "backward.fill") { media.previousTrack() }
                    ControlButton(symbol: info.isPlaying ? "pause.fill" : "play.fill", size: 20) {
                        media.togglePlayPause()
                    }
                    ControlButton(symbol: "forward.fill") { media.nextTrack() }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 14) {
            ArtworkView(image: nil, size: 92, cornerRadius: 14)
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing playing")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(media.sourceDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    var cornerRadius: CGFloat = 8
    var badge: NSImage? = nil

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [Color.white.opacity(0.14), Color.white.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.38, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if let badge {
                Image(nsImage: badge)
                    .resizable()
                    .frame(width: size * 0.3, height: size * 0.3)
                    .offset(x: size * 0.07, y: size * 0.07)
            }
        }
        .contentShape(Rectangle())
    }
}

struct ControlButton: View {
    let symbol: String
    var size: CGFloat = 15
    let action: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: size + 20, height: size + 14)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct ProgressScrubber: View {
    let info: NowPlayingInfo
    let accent: Color
    let onSeek: (Double) -> Void
    @State var dragFraction: Double? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = info.currentElapsed(at: context.date)
            let fraction = dragFraction ?? (info.duration > 0 ? min(1, max(0, elapsed / info.duration)) : 0)
            let shownElapsed = dragFraction.map { $0 * info.duration } ?? elapsed

            VStack(spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(accent)
                            .frame(width: max(0, geo.size.width * CGFloat(fraction)))
                    }
                    .frame(height: dragFraction == nil ? 5 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard info.duration > 0 else { return }
                                dragFraction = clamp(value.location.x / max(1, geo.size.width))
                            }
                            .onEnded { value in
                                guard info.duration > 0 else { return }
                                let target = clamp(value.location.x / max(1, geo.size.width))
                                onSeek(target * info.duration)
                                dragFraction = nil
                            }
                    )
                }
                .frame(height: 10)
                .animation(.easeOut(duration: 0.15), value: dragFraction == nil)

                HStack {
                    Text(formatTime(shownElapsed))
                    Spacer()
                    Text(info.duration > 0 ? "-" + formatTime(max(0, info.duration - shownElapsed)) : "--:--")
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundColor(.white.opacity(0.45))
            }
        }
    }

    private func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "--:--" }
    let total = Int(seconds.rounded(.down))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}
