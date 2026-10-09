import AppKit
import SwiftUI

struct ShelfView: View {
    let isDropTargeted: Bool
    @ObservedObject var shelf = ShelfStore.shared

    var body: some View {
        if shelf.items.isEmpty {
            dropZone
        } else {
            VStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shelf.items) { item in
                            ShelfItemView(item: item)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(isDropTargeted ? 0.5 : 0), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                )

                HStack(spacing: 8) {
                    Text("\(shelf.items.count) item\(shelf.items.count == 1 ? "" : "s") · drag out to use")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    ShelfActionButton(title: "AirDrop", symbol: "dot.radiowaves.left.and.right") {
                        shelf.airDrop(shelf.items)
                    }
                    ShelfActionButton(title: "Clear", symbol: "xmark") {
                        shelf.clear()
                    }
                }
            }
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(
                Color.white.opacity(isDropTargeted ? 0.6 : 0.2),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
            )
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(isDropTargeted ? 0.08 : 0.03))
            )
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                        .font(.system(size: 22, weight: .medium))
                    Text(isDropTargeted ? "Release to add" : "Drop files here to keep them handy")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white.opacity(isDropTargeted ? 0.9 : 0.45))
            )
            .animation(.easeOut(duration: 0.15), value: isDropTargeted)
    }
}

struct ShelfItemView: View {
    let item: ShelfItem
    @State var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 44, height: 44)
            Text(item.url.lastPathComponent)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 72)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hovering ? 0.1 : 0)))
        .onHover { hovering = $0 }
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(item.url)
        }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(item.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button("AirDrop") { ShelfStore.shared.airDrop([item]) }
            Divider()
            Button("Remove from Shelf") { ShelfStore.shared.remove(item) }
        }
        .help(item.url.path)
    }
}

struct ShelfActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}
