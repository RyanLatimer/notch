import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var media = MediaManager.shared
    @ObservedObject var settings = AppSettings.shared

    let spring = Animation.spring(response: 0.42, dampingFraction: 0.8)

    var body: some View {
        VStack(spacing: 0) {
            notch
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var notch: some View {
        let size = vm.frameSize
        let shape = NotchShape(topRadius: vm.topRadius, bottomRadius: vm.bottomRadius)

        return ZStack(alignment: .top) {
            shape.fill(Color.black)
            content
                .padding(.horizontal, vm.topRadius)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .contentShape(shape)
        .shadow(color: .black.opacity(vm.state == .expanded ? 0.55 : 0), radius: 14, y: 4)
        .animation(spring, value: vm.layoutKey)
        .onTapGesture {
            if vm.state == .collapsed { vm.tappedCollapsed() }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $vm.isDropTargeted) { providers in
            vm.handleDrop(providers)
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        if vm.state == .expanded {
            ExpandedView(vm: vm)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).animation(spring.delay(0.05)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))
                ))
        } else if let transient = vm.transient {
            TransientActivityView(activity: transient, notchSize: vm.notchSize)
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        } else if vm.showsMusicActivity {
            MusicActivityView(notchSize: vm.notchSize)
                .transition(.opacity.animation(.easeInOut(duration: 0.25)))
        }
    }
}
