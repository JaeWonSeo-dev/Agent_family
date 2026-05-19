import SwiftUI
import AppKit
import CoreGraphics
import ApplicationServices
import Combine

@main
struct AgentFamilyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = TerminalStore()
    private var catWindows: [String: NSWindow] = [:]
    private var terminalsCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)

        terminalsCancellable = store.$terminals
            .receive(on: RunLoop.main)
            .sink { [weak self] terminals in
                self?.syncCatWindows(with: terminals)
            }

        store.startAutoRefresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        catWindows.values.forEach { $0.close() }
    }

}

private extension AppDelegate {
    func syncCatWindows(with terminals: [TerminalWindow]) {
        if terminals.isEmpty {
            catWindows
                .filter { $0.key != "empty" }
                .forEach { key, window in
                    window.close()
                    catWindows.removeValue(forKey: key)
                }
            upsertEmptyWindow()
            return
        }

        if let emptyWindow = catWindows.removeValue(forKey: "empty") {
            emptyWindow.close()
        }

        let activeIDs = Set(terminals.map(\.id))
        let staleWindows = catWindows.filter { !activeIDs.contains($0.key) }
        for (id, window) in staleWindows {
            window.close()
            catWindows.removeValue(forKey: id)
        }

        for (index, terminal) in terminals.enumerated() {
            let view = AnyView(
                FloatingTerminalCat(
                    terminal: terminal,
                    displayNumber: index + 1,
                    isSelected: true,
                    floatPhase: true,
                    onActivate: { [weak self] in self?.store.activate(terminal) },
                    onSolo: { [weak self] in self?.store.showOnly(terminal) },
                    onNewTab: { [weak self] in self?.store.openNewTab(in: terminal) },
                    onClear: { [weak self] in self?.store.sendClear(to: terminal) }
                )
            )

            if let window = catWindows[terminal.id] {
                (window.contentView as? TransparentHostingView<AnyView>)?.rootView = view
            } else {
                let window = makeCatWindow(
                    id: terminal.id,
                    origin: initialCatOrigin(for: index),
                    rootView: view
                )
                catWindows[terminal.id] = window
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func upsertEmptyWindow() {
        let view = AnyView(
            Plush3DCatIcon(
                tint: .gray,
                isSelected: false,
                displayNumber: 0,
                isAwake: true,
                isBlinking: false,
                isPointerNear: false,
                pointerVector: .zero,
                isHovering: false,
                isPressed: false,
                isDragging: false,
                isTerminalActive: false,
                mood: .idle,
                dragBounce: false
            )
                .frame(width: 146, height: 158)
                .contextMenu {
                    Button("새로고침") { self.store.refresh() }
                    Button("Agent Family 종료") { NSApplication.shared.terminate(nil) }
                }
                .help("감지된 터미널 없음 · 우클릭으로 새로고침")
        )

        if let window = catWindows["empty"] {
            (window.contentView as? TransparentHostingView<AnyView>)?.rootView = view
            return
        }

        let window = makeCatWindow(id: "empty", origin: initialCatOrigin(for: 0), rootView: view)
        catWindows["empty"] = window
        window.makeKeyAndOrderFront(nil)
    }

    func makeCatWindow(id: String, origin: CGPoint, rootView: AnyView) -> NSWindow {
        let size = NSSize(width: 158, height: 174)
        let window = FloatingOverlayWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let hostingView = TransparentHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: size)
        window.title = "Agent Family \(id)"
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        return window
    }

    func initialCatOrigin(for index: Int) -> CGPoint {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 80, y: 80, width: 900, height: 620)
        let column = index % 5
        let row = index / 5
        let x = screen.minX + 28 + CGFloat(column * 152)
        let y = screen.maxY - 190 - CGFloat(row * 164)
        return CGPoint(x: min(x, screen.maxX - 176), y: max(y, screen.minY + 20))
    }
}

@MainActor
final class OverlayWindowRegistry {
    static let shared = OverlayWindowRegistry()
    weak var window: NSWindow?
}

extension Notification.Name {
    static let agentFamilyScrollWheel = Notification.Name("AgentFamilyScrollWheel")
}

@MainActor
final class ScrollWheelRelay {
    static let shared = ScrollWheelRelay()

    private var scrollAccumulator: CGFloat = 0
    private let scrollThreshold: CGFloat = 7

    func handle(_ event: NSEvent) {
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY

        scrollAccumulator += delta
        guard abs(scrollAccumulator) >= scrollThreshold else { return }
        NotificationCenter.default.post(name: .agentFamilyScrollWheel, object: scrollAccumulator)
        scrollAccumulator = 0
    }
}

final class FloatingOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func scrollWheel(with event: NSEvent) {
        ScrollWheelRelay.shared.handle(event)
    }
}

final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        clearBackgrounds(from: self)
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }

    override func scrollWheel(with event: NSEvent) {
        ScrollWheelRelay.shared.handle(event)
    }

    private func clearBackgrounds(from view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        for subview in view.subviews {
            clearBackgrounds(from: subview)
        }
    }
}

struct FloatingTerminalOverlay: View {
    @EnvironmentObject private var store: TerminalStore
    @State private var selectedID: TerminalWindow.ID?
    @State private var iconPositions: [TerminalWindow.ID: CGPoint] = [:]
    @State private var floatPhase = false

    var body: some View {
        GeometryReader { proxy in
            Color.clear

            if store.terminals.isEmpty {
                emptyState
                    .position(x: 74, y: 74)
            } else {
                ForEach(Array(store.terminals.enumerated()), id: \.element.id) { index, terminal in
                    FloatingTerminalCat(
                        terminal: terminal,
                        displayNumber: index + 1,
                        isSelected: selectedID == terminal.id,
                        floatPhase: floatPhase,
                        onActivate: {
                            selectedID = terminal.id
                            store.activate(terminal)
                        },
                        onSolo: {
                            selectedID = terminal.id
                            store.showOnly(terminal)
                        },
                        onNewTab: {
                            selectedID = terminal.id
                            store.openNewTab(in: terminal)
                        },
                        onClear: {
                            selectedID = terminal.id
                            store.sendClear(to: terminal)
                        }
                    )
                    .position(position(for: terminal, index: index, in: proxy.size))
                    .gesture(
                        DragGesture(coordinateSpace: .named("overlay"))
                            .onChanged { value in
                                selectedID = terminal.id
                                iconPositions[terminal.id] = clamped(value.location, in: proxy.size)
                            }
                    )
                    .animation(.spring(response: 0.30, dampingFraction: 0.78), value: selectedID)
                }
            }
        }
        .background(.clear)
        .ignoresSafeArea()
        .coordinateSpace(name: "overlay")
        .onAppear {
            floatPhase = true
            selectedID = selectedID ?? store.terminals.first?.id
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentFamilyScrollWheel)) { notification in
            guard let deltaY = notification.object as? CGFloat else { return }
            stepSelection(deltaY: deltaY)
        }
        .onChange(of: store.terminals.count) { _, count in
            let validIDs = Set(store.terminals.map(\.id))
            iconPositions = iconPositions.filter { validIDs.contains($0.key) }
            if count == 0 {
                selectedID = nil
            } else if selectedID.map({ !validIDs.contains($0) }) ?? true {
                selectedID = store.terminals.first?.id
            }
        }
        .contextMenu {
            Button("새로고침") { store.refresh() }
            Button("Agent Family 종료") { NSApplication.shared.terminate(nil) }
        }
    }

    private func stepSelection(deltaY: CGFloat) {
        guard !store.terminals.isEmpty else { return }
        let step = deltaY < 0 ? 1 : -1
        let currentIndex = selectedID.flatMap { id in store.terminals.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + step, 0), store.terminals.count - 1)
        selectedID = store.terminals[nextIndex].id
    }

    private func position(for terminal: TerminalWindow, index: Int, in size: CGSize) -> CGPoint {
        if let position = iconPositions[terminal.id] {
            return clamped(position, in: size)
        }

        let columns = max(1, Int(size.width / 130))
        let row = index / columns
        let column = index % columns
        let x = CGFloat(74 + column * 118)
        let y = CGFloat(82 + row * 126)
        return clamped(CGPoint(x: x, y: y), in: size)
    }

    private func clamped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 48), max(48, size.width - 48)),
            y: min(max(point.y, 54), max(54, size.height - 54))
        )
    }

    private var emptyState: some View {
        Plush3DCatIcon(
            tint: .gray,
            isSelected: false,
            displayNumber: 0,
            isAwake: true,
            isBlinking: false,
            isPointerNear: false,
            pointerVector: .zero,
            isHovering: false,
            isPressed: false,
            isDragging: false,
            isTerminalActive: false,
            mood: .idle,
            dragBounce: false
        )
            .help("감지된 터미널 없음 · 우클릭으로 새로고침")
    }
}

struct FloatingTerminalCat: View {
    let terminal: TerminalWindow
    let displayNumber: Int
    let isSelected: Bool
    let floatPhase: Bool
    let onActivate: () -> Void
    let onSolo: () -> Void
    let onNewTab: () -> Void
    let onClear: () -> Void
    @State private var livePhase = false
    @State private var blinkPhase = false
    @State private var windowFrameProvider: (() -> CGRect)?
    @State private var windowProvider: (() -> NSWindow?)?
    @State private var pointerVector = CGSize.zero
    @State private var isPointerNear = false
    @State private var isHovering = false
    @State private var isPressed = false
    @State private var isDragging = false
    @State private var dragStartFrame: CGRect?
    @State private var dragBounce = false
    @State private var isTerminalActive = false
    private let pointerTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 6) {
            if isSelected {
                TerminalSpeechBubble(text: terminal.displayPath)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            Plush3DCatIcon(
                tint: terminal.tint,
                isSelected: isSelected,
                displayNumber: displayNumber,
                isAwake: livePhase,
                isBlinking: blinkPhase,
                isPointerNear: isPointerNear,
                pointerVector: pointerVector,
                isHovering: isHovering,
                isPressed: isPressed,
                isDragging: isDragging,
                isTerminalActive: isTerminalActive,
                mood: terminal.mood,
                dragBounce: dragBounce
            )
                .offset(y: floatPhase ? -4 : 4)
                .animation(
                    .easeInOut(duration: 1.7 + Double(displayNumber % 4) * 0.18)
                        .repeatForever(autoreverses: true),
                    value: floatPhase
                )
                .onTapGesture(count: 2, perform: onSolo)
                .onTapGesture {
                    pressAndActivate()
                }
        }
        .frame(width: 146, height: 158)
        .contentShape(Rectangle())
        .background(WindowFrameReader(frameProvider: $windowFrameProvider, windowProvider: $windowProvider))
        .onHover { hovering in
            isHovering = hovering
        }
        .simultaneousGesture(dragGesture)
        .onAppear {
            livePhase = true
            scheduleBlink()
        }
        .onReceive(pointerTimer) { _ in
            updatePointerReaction()
        }
        .contextMenu {
            Button("앞으로 가져오기", action: onActivate)
            Button("이 터미널만 보기", action: onSolo)
            Divider()
            Button("새 탭 열기", action: onNewTab)
            Button("clear 입력", action: onClear)
            Divider()
            Text(terminal.shortTitle)
        }
        .help("\(terminal.appName): \(terminal.title.isEmpty ? "Untitled" : terminal.title)")
    }

    private func scheduleBlink() {
        let delay = 1.6 + Double(displayNumber % 5) * 0.43
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            blinkPhase = true
            try? await Task.sleep(nanoseconds: 120_000_000)
            blinkPhase = false
            scheduleBlink()
        }
    }

    private func updatePointerReaction() {
        let windowFrame = windowFrameProvider?() ?? .zero
        guard !windowFrame.isEmpty else { return }

        isTerminalActive = NSWorkspace.shared.frontmostApplication?.processIdentifier == terminal.processID
        let mouse = NSEvent.mouseLocation
        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        let dx = mouse.x - center.x
        let dy = mouse.y - center.y
        let distance = max(1, hypot(dx, dy))
        let nearDistance: CGFloat = 220
        let strength = max(0, min(1, 1 - distance / nearDistance))

        isPointerNear = strength > 0.12
        pointerVector = CGSize(width: dx / distance * strength, height: dy / distance * strength)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStartFrame == nil {
                    dragStartFrame = windowFrameProvider?() ?? .zero
                }
                guard let startFrame = dragStartFrame, let window = windowProvider?() else { return }

                isDragging = true
                isPressed = true
                let newOrigin = CGPoint(
                    x: startFrame.origin.x + value.translation.width,
                    y: startFrame.origin.y - value.translation.height
                )
                window.setFrameOrigin(clampedWindowOrigin(newOrigin, size: startFrame.size))
            }
            .onEnded { value in
                let distance = hypot(value.translation.width, value.translation.height)
                if distance < 5 {
                    pressAndActivate()
                }

                isDragging = false
                isPressed = false
                dragStartFrame = nil
                triggerDragBounce()
            }
    }

    private func clampedWindowOrigin(_ origin: CGPoint, size: CGSize) -> CGPoint {
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(CGRect(origin: origin, size: size)) })
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return origin }

        return CGPoint(
            x: min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        )
    }

    private func pressAndActivate() {
        isPressed = true
        onActivate()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 130_000_000)
            isPressed = false
        }
    }

    private func triggerDragBounce() {
        dragBounce = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            dragBounce = false
        }
    }
}

struct WindowFrameReader: NSViewRepresentable {
    @Binding var frameProvider: (() -> CGRect)?
    @Binding var windowProvider: (() -> NSWindow?)?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            frameProvider = { [weak view] in
                view?.window?.frame ?? .zero
            }
            windowProvider = { [weak view] in
                view?.window
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            frameProvider = { [weak nsView] in
                nsView?.window?.frame ?? .zero
            }
            windowProvider = { [weak nsView] in
                nsView?.window
            }
        }
    }
}

struct TerminalSpeechBubble: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.94))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                )

            Triangle()
                .fill(.black.opacity(0.58))
                .frame(width: 14, height: 8)
        }
        .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: 4)
        .frame(maxWidth: 220)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct Plush3DCatIcon: View {
    let tint: Color
    let isSelected: Bool
    let displayNumber: Int
    let isAwake: Bool
    let isBlinking: Bool
    let isPointerNear: Bool
    let pointerVector: CGSize
    let isHovering: Bool
    let isPressed: Bool
    let isDragging: Bool
    let isTerminalActive: Bool
    let mood: TerminalMood
    let dragBounce: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                mascotAura

                if let catImage = isPointerNear ? CatIconAsset.focusImage : CatIconAsset.idleImage {
                    Image(nsImage: catImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 144, height: 144)
                        .offset(
                            x: pointerVector.width * (isDragging ? 16 : 9),
                            y: -pointerVector.height * (isDragging ? 13 : 8) + (isPressed ? 7 : 0)
                        )
                        .scaleEffect(
                            x: mascotScaleX,
                            y: mascotScaleY,
                            anchor: .bottom
                        )
                        .rotationEffect(
                            .degrees(Double(pointerVector.width * 10) + idleTilt),
                            anchor: .bottom
                        )
                        .shadow(color: effectiveMood.color.opacity(isTerminalActive ? 0.38 : 0.18), radius: isTerminalActive ? 18 : 10, x: 0, y: 8)
                        .animation(
                            .easeInOut(duration: 2.6 + Double(displayNumber % 4) * 0.13)
                                .repeatForever(autoreverses: true),
                            value: isAwake
                        )
                        .animation(.spring(response: 0.24, dampingFraction: 0.74), value: isPointerNear)
                        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.82), value: pointerVector)
                } else {
                    vectorFallbackCat
                }

                if isPointerNear || isHovering || isTerminalActive {
                    pointerFocusGlint
                }

                Image(systemName: "terminal.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.94))
                    .frame(width: 20, height: 20)
                    .background(effectiveMood.color.opacity(0.92), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 1))
                    .scaleEffect(isTerminalActive ? 1.12 : 1.0)
                    .offset(x: 44, y: 55 + (isPressed ? 3 : 0))
            }
            .frame(width: 146, height: 146)
            .shadow(color: effectiveMood.color.opacity(isSelected ? 0.24 : 0.10), radius: isSelected ? 20 : 10, x: 0, y: 8)
            .shadow(color: .black.opacity(isPressed ? 0.10 : 0.18), radius: isPressed ? 5 : 10, x: 0, y: isPressed ? 3 : 8)
            .offset(y: dragBounce ? -5 : 0)
            .animation(.spring(response: 0.26, dampingFraction: 0.48), value: dragBounce)
            .animation(.spring(response: 0.18, dampingFraction: 0.72), value: isPressed)

            if displayNumber > 0 {
                Text("\(displayNumber)")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(effectiveMood.color, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                    .offset(x: -2, y: -6)
            }
        }
    }

    private var mascotScaleX: CGFloat {
        if isPressed { return 1.08 }
        if isDragging { return 1.04 }
        if isHovering || isPointerNear { return 1.035 }
        return isAwake ? 1.018 : 0.992
    }

    private var mascotScaleY: CGFloat {
        if isPressed { return 0.90 }
        if isDragging { return 0.96 }
        if isHovering || isPointerNear { return 1.015 }
        return isAwake ? 0.992 : 1.018
    }

    private var idleTilt: Double {
        if isPressed { return 0 }
        if isDragging { return Double(pointerVector.width * 12) }
        return isAwake ? 0.8 : -0.8
    }

    private var effectiveMood: TerminalMood {
        isTerminalActive && mood == .idle ? .active : mood
    }

    private var mascotAura: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            effectiveMood.color.opacity(isTerminalActive ? 0.30 : 0.16),
                            effectiveMood.color.opacity(0.04),
                            .clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 74
                    )
                )
                .frame(width: isHovering || isPointerNear ? 136 : 118, height: isHovering || isPointerNear ? 136 : 118)
                .blur(radius: 6)

            Capsule()
                .fill(.black.opacity(isPressed ? 0.12 : 0.18))
                .frame(width: isPressed ? 82 : 96, height: isPressed ? 14 : 18)
                .blur(radius: 7)
                .offset(y: 66)
        }
        .animation(.easeInOut(duration: 0.18), value: isHovering)
        .animation(.easeInOut(duration: 0.18), value: isPointerNear)
        .animation(.easeInOut(duration: 0.18), value: isTerminalActive)
    }

    private var pointerFocusGlint: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(isTerminalActive ? 0.75 : 0.55))
                .frame(width: 6, height: 6)
                .offset(x: 26 + pointerVector.width * 6, y: -23 - pointerVector.height * 5)

            effectiveMood.symbol
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(effectiveMood.color.opacity(0.88), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.70), lineWidth: 1))
                .offset(x: -45, y: -50)
                .scaleEffect(isTerminalActive ? 1.08 : 1.0)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.88)))
    }

    private var vectorFallbackCat: some View {
        ZStack {
            cloud
                .offset(y: 25)
                .scaleEffect(x: isAwake ? 1.02 : 0.98, y: isAwake ? 0.98 : 1.02)
                .animation(
                    .easeInOut(duration: 2.1 + Double(displayNumber % 4) * 0.13)
                        .repeatForever(autoreverses: true),
                    value: isAwake
                )

            tail
                .offset(x: -34, y: 18)

            catBody
                .offset(y: 7)

            head
                .offset(y: isAwake ? -19 : -15)
                .rotationEffect(.degrees(isAwake ? 1.8 : -1.8))
                .scaleEffect(isBlinking ? 0.985 : 1)
                .animation(
                    .easeInOut(duration: 2.3 + Double(displayNumber % 3) * 0.16)
                        .repeatForever(autoreverses: true),
                    value: isAwake
                )

            frontPaw(x: -18)
            frontPaw(x: 19)
        }
    }

    private var cloud: some View {
        ZStack {
            CloudPuff(width: 88, height: 38, x: 0, y: 6)
            CloudPuff(width: 45, height: 43, x: -38, y: 0)
            CloudPuff(width: 46, height: 46, x: -15, y: -10)
            CloudPuff(width: 52, height: 50, x: 16, y: -8)
            CloudPuff(width: 45, height: 42, x: 40, y: 2)
            CloudPuff(width: 32, height: 32, x: -3, y: 17)
                .opacity(0.95)
        }
        .overlay(
            Ellipse()
                .fill(.pink.opacity(0.16))
                .frame(width: 100, height: 23)
                .blur(radius: 7)
                .offset(y: 18)
        )
    }

    private var catBody: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.86, blue: 0.82),
                        Color(red: 0.94, green: 0.72, blue: 0.70),
                        Color(red: 0.70, green: 0.45, blue: 0.47).opacity(0.88)
                    ],
                    center: .topLeading,
                    startRadius: 6,
                    endRadius: 58
                )
            )
            .frame(width: 64, height: 46)
            .overlay(Ellipse().stroke(.white.opacity(0.38), lineWidth: 1))
            .shadow(color: .white.opacity(0.20), radius: 5, x: -4, y: -5)
            .shadow(color: .pink.opacity(0.20), radius: 7, x: 2, y: 5)
    }

    private var head: some View {
        ZStack {
            CatEar()
                .fill(earGradient)
                .frame(width: 27, height: 29)
                .overlay(CatEar().fill(.pink.opacity(0.54)).padding(7))
                .rotationEffect(.degrees(-26))
                .offset(x: -23, y: -20)

            CatEar()
                .fill(earGradient)
                .frame(width: 27, height: 29)
                .overlay(CatEar().fill(.pink.opacity(0.54)).padding(7))
                .rotationEffect(.degrees(26))
                .offset(x: 23, y: -20)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.91, blue: 0.88),
                            Color(red: 0.95, green: 0.73, blue: 0.70),
                            Color(red: 0.70, green: 0.45, blue: 0.47).opacity(0.82)
                        ],
                        center: .topLeading,
                        startRadius: 7,
                        endRadius: 58
                    )
                )
                .frame(width: 72, height: 66)
                .overlay(Circle().stroke(.white.opacity(0.32), lineWidth: 1))

            ForEach([-12, 0, 12], id: \.self) { x in
                ForeheadStripe()
                    .fill(Color(red: 0.56, green: 0.37, blue: 0.33).opacity(0.42))
                    .frame(width: 7, height: 19)
                    .offset(x: CGFloat(x), y: -25)
            }

            ClosedEye()
                .stroke(Color(red: 0.28, green: 0.15, blue: 0.15).opacity(0.86), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 18, height: 8)
                .offset(x: -15, y: -5)

            ClosedEye()
                .stroke(Color(red: 0.28, green: 0.15, blue: 0.15).opacity(0.86), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 18, height: 8)
                .scaleEffect(x: -1, y: 1)
                .offset(x: 15, y: -5)

            HStack(spacing: 42) {
                Whiskers()
                    .stroke(Color(red: 0.42, green: 0.24, blue: 0.23).opacity(0.36), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    .frame(width: 22, height: 15)
                Whiskers()
                    .stroke(Color(red: 0.42, green: 0.24, blue: 0.23).opacity(0.36), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    .frame(width: 22, height: 15)
                    .scaleEffect(x: -1, y: 1)
            }
            .offset(y: 11)

            Triangle()
                .fill(Color(red: 0.88, green: 0.37, blue: 0.34))
                .frame(width: 9, height: 7)
                .rotationEffect(.degrees(180))
                .offset(y: 8)

            CatMouth(isOpen: false)
                .stroke(Color(red: 0.35, green: 0.18, blue: 0.18).opacity(0.72), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .frame(width: 25, height: 14)
                .offset(y: 16)
        }
    }

    private func frontPaw(x: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.86, blue: 0.84),
                        Color(red: 0.86, green: 0.58, blue: 0.58).opacity(0.95)
                    ],
                    center: .topLeading,
                    startRadius: 2,
                    endRadius: 20
                )
            )
            .frame(width: 20, height: 20)
            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
            .offset(x: x, y: 27)
    }

    private var tail: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.80, blue: 0.77),
                        Color(red: 0.78, green: 0.47, blue: 0.48)
                    ],
                    center: .topLeading,
                    startRadius: 2,
                    endRadius: 18
                )
            )
            .frame(width: 24, height: 24)
            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
    }

    private var earGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.86, blue: 0.82),
                Color(red: 0.84, green: 0.58, blue: 0.56)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct CloudPuff: View {
    let width: CGFloat
    let height: CGFloat
    let x: CGFloat
    let y: CGFloat

    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        .white.opacity(0.98),
                        Color(red: 1.0, green: 0.79, blue: 0.80).opacity(0.88),
                        Color(red: 0.78, green: 0.52, blue: 0.58).opacity(0.72)
                    ],
                    center: .topLeading,
                    startRadius: 3,
                    endRadius: 48
                )
            )
            .frame(width: width, height: height)
            .shadow(color: .white.opacity(0.26), radius: 4, x: -3, y: -4)
            .shadow(color: .pink.opacity(0.24), radius: 7, x: 2, y: 5)
            .offset(x: x, y: y)
    }
}

enum CatIconAsset {
    static let idleFileName = "cat-idle-groom.png"
    static let focusFileName = "cat-alert-focus.png"

    static var idleImage: NSImage? {
        image(named: idleFileName) ?? image(named: "plush-cat.png")
    }

    static var focusImage: NSImage? {
        image(named: focusFileName) ?? idleImage
    }

    private static func image(named fileName: String) -> NSImage? {
        for url in candidateURLs(for: fileName) {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }

    private static func candidateURLs(for fileName: String) -> [URL] {
        var urls: [URL] = []

        if let bundleURL = Bundle.main.resourceURL {
            urls.append(bundleURL.appendingPathComponent(fileName))
        }

        let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        urls.append(currentDirectoryURL.appendingPathComponent("AppResources/\(fileName)"))
        urls.append(currentDirectoryURL.appendingPathComponent("Resources/\(fileName)"))

        if let executableURL = Bundle.main.executableURL {
            urls.append(
                executableURL
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Resources/\(fileName)")
            )
        }

        return urls
    }
}

struct ClosedEye: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.maxY + 3)
        )
        return path
    }
}

struct ForeheadStripe: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.minX - 1, y: rect.height * 0.30),
            control2: CGPoint(x: rect.maxX + 1, y: rect.height * 0.68)
        )
        return path
    }
}

struct CatMouth: Shape {
    let isOpen: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.minY + 2)
        path.move(to: center)
        path.addQuadCurve(
            to: CGPoint(x: rect.midX - rect.width * 0.30, y: rect.midY),
            control: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.midY + 4)
        )
        path.move(to: center)
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + rect.width * 0.30, y: rect.midY),
            control: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.midY + 4)
        )

        if isOpen {
            path.addEllipse(in: CGRect(x: rect.midX - 3, y: rect.midY + 2, width: 6, height: 7))
        }

        return path
    }
}

struct CatTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 5, y: rect.maxY - 6))
        path.addCurve(
            to: CGPoint(x: rect.maxX - 8, y: rect.minY + 8),
            control1: CGPoint(x: rect.maxX + 8, y: rect.maxY - 8),
            control2: CGPoint(x: rect.maxX + 2, y: rect.minY + 30)
        )
        return path
    }
}

struct Whiskers: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.midY - 3))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 2))
        path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.midY + 3))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 2))
        return path
    }
}

struct CatEar: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

enum TerminalMood: Equatable {
    case idle
    case active
    case running
    case success
    case error

    static func inferred(from title: String) -> TerminalMood {
        let lowered = title.lowercased()
        if lowered.contains("error")
            || lowered.contains("failed")
            || lowered.contains("exception")
            || lowered.contains("panic") {
            return .error
        }
        if lowered.contains("success")
            || lowered.contains("passed")
            || lowered.contains("complete")
            || lowered.contains("done") {
            return .success
        }
        if lowered.contains("running")
            || lowered.contains("building")
            || lowered.contains("installing")
            || lowered.contains("watch")
            || lowered.contains("npm")
            || lowered.contains("swift build") {
            return .running
        }
        return .idle
    }

    var color: Color {
        switch self {
        case .idle:
            return .pink
        case .active:
            return .cyan
        case .running:
            return .orange
        case .success:
            return .green
        case .error:
            return .red
        }
    }

    var symbol: Image {
        switch self {
        case .idle:
            return Image(systemName: "moon.zzz.fill")
        case .active:
            return Image(systemName: "eye.fill")
        case .running:
            return Image(systemName: "bolt.fill")
        case .success:
            return Image(systemName: "checkmark")
        case .error:
            return Image(systemName: "exclamationmark")
        }
    }
}

struct TerminalWindow: Identifiable, Equatable {
    let appName: String
    let bundleIdentifier: String
    let processID: Int32
    let windowIndex: Int
    let title: String
    let windowNumber: Int?
    let windowFrame: CGRect?
    let tty: String?
    let currentPath: String?

    var id: String { "\(bundleIdentifier)-\(processID)-\(windowIndex)-\(windowNumber ?? 0)-\(title)" }

    var iconSystemName: String {
        bundleIdentifier.contains("iterm") ? "apple.terminal.on.rectangle" : "terminal"
    }

    var tint: Color {
        bundleIdentifier.contains("iterm") ? .purple : .green
    }

    var mood: TerminalMood {
        TerminalMood.inferred(from: title)
    }

    var shortTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return appName }
        return String(trimmed.prefix(14))
    }

    var displayPath: String {
        if let currentPath, !currentPath.isEmpty {
            return currentPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
        if let tty, !tty.isEmpty {
            return tty
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }
}

@MainActor
final class TerminalStore: ObservableObject {
    @Published var terminals: [TerminalWindow] = []

    private var refreshTimer: Timer?
    private let supportedApps: [TerminalAppDescriptor] = [
        .init(displayName: "Terminal", bundleIdentifier: "com.apple.Terminal"),
        .init(displayName: "iTerm2", bundleIdentifier: "com.googlecode.iterm2")
    ]

    func startAutoRefresh() {
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        terminals = supportedApps.flatMap { descriptor -> [TerminalWindow] in
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: descriptor.bundleIdentifier).first else {
                return []
            }
            return fetchWindows(for: descriptor, processID: app.processIdentifier)
        }
        .sorted { lhs, rhs in
            if lhs.appName == rhs.appName { return lhs.windowIndex < rhs.windowIndex }
            return lhs.appName < rhs.appName
        }
    }

    func activate(_ terminal: TerminalWindow) {
        if !activateSingleLinkedTerminal(terminal), !activateSingleLinkedTerminalUsingAppleScript(terminal) {
            NSLog("Could not activate linked terminal window: %@", terminal.id)
        }

        refresh()
    }

    func showOnly(_ terminal: TerminalWindow) {
        activate(terminal)
    }

    func openNewTab(in terminal: TerminalWindow) {
        activate(terminal)
        let appName = terminal.bundleIdentifier == "com.apple.Terminal" ? "Terminal" : "iTerm2"
        let script = """
        tell application "\(appName)" to activate
        delay 0.05
        tell application "System Events"
            keystroke "t" using command down
        end tell
        """
        _ = runAppleScript(script)
        refresh()
    }

    func sendClear(to terminal: TerminalWindow) {
        activate(terminal)

        let script: String
        if terminal.bundleIdentifier == "com.apple.Terminal" {
            script = """
            tell application "Terminal"
                do script "clear" in selected tab of front window
                activate
            end tell
            """
        } else {
            script = """
            tell application "iTerm2"
                tell current session of front window
                    write text "clear"
                end tell
                activate
            end tell
            """
        }

        _ = runAppleScript(script)
        refresh()
    }

    private func activateSingleLinkedTerminal(_ terminal: TerminalWindow) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let windows = currentAXTerminalWindows()
        guard let target = targetAXTerminalWindow(for: terminal, in: windows) else {
            return false
        }

        for window in windows where !CFEqual(window.element, target.element) {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }

        let unminimizeResult = AXUIElementSetAttributeValue(target.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)

        for window in windows where !CFEqual(window.element, target.element) {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }

        let frontmostResult = AXUIElementSetAttributeValue(target.appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        let mainResult = AXUIElementSetAttributeValue(target.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        let focusResult = AXUIElementSetAttributeValue(target.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        let raiseResult = AXUIElementPerformAction(target.element, kAXRaiseAction as CFString)

        return unminimizeResult == .success
            || frontmostResult == .success
            || mainResult == .success
            || focusResult == .success
            || raiseResult == .success
    }

    private func activateSingleLinkedTerminalUsingAppleScript(_ terminal: TerminalWindow) -> Bool {
        let targetAppName = terminal.bundleIdentifier == "com.apple.Terminal" ? "Terminal" : "iTerm2"
        let otherAppName = terminal.bundleIdentifier == "com.apple.Terminal" ? "iTerm2" : "Terminal"
        let escapedTitle = terminal.title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let targetID = terminal.windowNumber.map(String.init) ?? ""
        let targetIndex = max(terminal.windowIndex, 1)

        let targetLookup: String
        if let windowNumber = terminal.windowNumber {
            targetLookup = """
                    repeat with w in windows
                        try
                            if id of w is \(windowNumber) then
                                set targetWindow to w
                                exit repeat
                            end if
                        end try
                    end repeat
            """
        } else {
            targetLookup = """
                    try
                        set targetWindow to window \(targetIndex)
                    end try
            """
        }

        let titleFallback = """
                if targetWindow is missing value then
                    repeat with w in windows
                        try
                            if name of w is "\(escapedTitle)" then
                                set targetWindow to w
                                exit repeat
                            end if
                        end try
                    end repeat
                end if
        """

        let targetIDScript = targetID.isEmpty ? "missing value" : targetID
        let script = """
        if application "\(otherAppName)" is running then
            tell application "\(otherAppName)"
                repeat with w in windows
                    try
                        set miniaturized of w to true
                    end try
                end repeat
            end tell
        end if

        if application "\(targetAppName)" is not running then
            return "missing"
        end if

        tell application "\(targetAppName)"
            set targetWindow to missing value
            set targetID to \(targetIDScript)
            \(targetLookup)
            \(titleFallback)
            if targetWindow is missing value then
                try
                    set targetWindow to window \(targetIndex)
                end try
            end if
            if targetWindow is missing value then
                return "missing"
            end if

            try
                set targetID to id of targetWindow
            end try

            repeat with w in windows
                try
                    if id of w is not targetID then
                        set miniaturized of w to true
                    end if
                on error
                    try
                        if w is not targetWindow then
                            set miniaturized of w to true
                        end if
                    end try
                end try
            end repeat

            set miniaturized of targetWindow to false
            try
                set visible of targetWindow to true
            end try
            set index of targetWindow to 1
            try
                select targetWindow
            end try
            activate

            repeat with w in windows
                try
                    if id of w is not targetID then
                        set miniaturized of w to true
                    end if
                on error
                    try
                        if w is not targetWindow then
                            set miniaturized of w to true
                        end if
                    end try
                end try
            end repeat
            set index of targetWindow to 1
            try
                select targetWindow
            end try
            return "ok"
        end tell
        """

        return runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines) == "ok"
    }

    private struct AXTerminalWindow {
        let appElement: AXUIElement
        let element: AXUIElement
        let bundleIdentifier: String
        let processID: pid_t
        let windowNumber: Int?
        let title: String
        let frame: CGRect?
    }

    private func currentAXTerminalWindows() -> [AXTerminalWindow] {
        supportedApps.flatMap { descriptor -> [AXTerminalWindow] in
            NSRunningApplication
                .runningApplications(withBundleIdentifier: descriptor.bundleIdentifier)
                .flatMap { app -> [AXTerminalWindow] in
                    let appElement = AXUIElementCreateApplication(app.processIdentifier)
                    var rawWindows: CFTypeRef?
                    let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &rawWindows)
                    guard result == .success, let windows = rawWindows as? [AXUIElement] else {
                        return []
                    }

                    return windows.compactMap { window in
                        axTerminalWindow(
                            from: window,
                            appElement: appElement,
                            bundleIdentifier: descriptor.bundleIdentifier,
                            processID: app.processIdentifier
                        )
                    }
                }
        }
    }

    private func axTerminalWindow(
        from window: AXUIElement,
        appElement: AXUIElement,
        bundleIdentifier: String,
        processID: pid_t
    ) -> AXTerminalWindow? {
        var rawRole: CFTypeRef?
        var rawSubrole: CFTypeRef?
        var rawWindowNumber: CFTypeRef?
        var rawTitle: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &rawRole)
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &rawSubrole)
        AXUIElementCopyAttributeValue(window, "AXWindowNumber" as CFString, &rawWindowNumber)
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &rawTitle)

        let role = rawRole as? String
        let subrole = rawSubrole as? String
        guard role == kAXWindowRole as String else { return nil }
        guard subrole == nil || subrole == kAXStandardWindowSubrole as String else { return nil }

        return AXTerminalWindow(
            appElement: appElement,
            element: window,
            bundleIdentifier: bundleIdentifier,
            processID: processID,
            windowNumber: intValue(from: rawWindowNumber),
            title: normalizeTitle(rawTitle as? String ?? ""),
            frame: axFrame(for: window)
        )
    }

    private func targetAXTerminalWindow(for terminal: TerminalWindow, in windows: [AXTerminalWindow]) -> AXTerminalWindow? {
        let sameAppWindows = windows.filter {
            $0.bundleIdentifier == terminal.bundleIdentifier && $0.processID == terminal.processID
        }

        if let windowNumber = terminal.windowNumber,
           let match = sameAppWindows.first(where: { $0.windowNumber == windowNumber }) {
            return match
        }

        if let targetFrame = terminal.windowFrame,
           let frameMatch = sameAppWindows
            .compactMap({ window -> (window: AXTerminalWindow, distance: CGFloat)? in
                guard let frame = window.frame else { return nil }
                return (window, frameDistance(frame, targetFrame))
            })
            .min(by: { $0.distance < $1.distance }),
           frameMatch.distance <= 8 {
            return frameMatch.window
        }

        let normalizedTitle = normalizeTitle(terminal.title)
        let titleMatches = sameAppWindows.filter { $0.title == normalizedTitle }
        if titleMatches.count == 1 {
            return titleMatches[0]
        }

        guard terminal.windowIndex > 0, terminal.windowIndex <= sameAppWindows.count else {
            return nil
        }
        return sameAppWindows[terminal.windowIndex - 1]
    }

    private func axFrame(for window: AXUIElement) -> CGRect? {
        var rawPosition: CFTypeRef?
        var rawSize: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &rawPosition)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &rawSize)

        var point = CGPoint.zero
        var size = CGSize.zero
        guard let positionValue = rawPosition, AXValueGetValue(positionValue as! AXValue, .cgPoint, &point) else { return nil }
        guard let sizeValue = rawSize, AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.origin.x - rhs.origin.x)
        + abs(lhs.origin.y - rhs.origin.y)
        + abs(lhs.width - rhs.width)
        + abs(lhs.height - rhs.height)
    }

    private func normalizeTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func intValue(from value: CFTypeRef?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        return value as? Int
    }

    private func fetchWindows(for descriptor: TerminalAppDescriptor, processID: pid_t) -> [TerminalWindow] {
        let accessibilityWindows = deduplicated(fetchWindowsUsingAccessibility(for: descriptor, processID: processID))
        if !accessibilityWindows.isEmpty {
            return accessibilityWindows
        }

        let windowServerWindows = deduplicated(fetchWindowsUsingWindowServer(for: descriptor, processID: processID))
        if !windowServerWindows.isEmpty {
            return windowServerWindows
        }

        return fetchWindowsUsingAppleScript(for: descriptor, processID: processID)
    }

    private func fetchWindowsUsingAppleScript(for descriptor: TerminalAppDescriptor, processID: pid_t) -> [TerminalWindow] {
        let appName = descriptor.bundleIdentifier == "com.apple.Terminal" ? "Terminal" : "iTerm2"
        let script = """
        tell application "\(appName)"
            set output to ""
            repeat with i from 1 to count of windows
                set w to window i
                try
                    set windowID to id of w as text
                on error
                    set windowID to ""
                end try
                try
                    if "\(appName)" is "Terminal" then
                        set terminalTTY to tty of selected tab of w as text
                    else
                        set terminalTTY to tty of current session of w as text
                    end if
                on error
                    set terminalTTY to ""
                end try
                set output to output & i & tab & windowID & tab & terminalTTY & tab & (name of w as text) & linefeed
            end repeat
            return output
        end tell
        """

        return runAppleScript(script)
            .split(separator: "\n")
            .compactMap { line -> TerminalWindow? in
                let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
                guard let indexPart = parts.first, let index = Int(indexPart) else { return nil }
                let windowID = parts.count > 1 ? Int(parts[1]) : nil
                let tty = parts.count > 2 ? String(parts[2]) : ""
                let title = parts.count > 3 ? String(parts[3]) : ""
                return TerminalWindow(
                    appName: descriptor.displayName,
                    bundleIdentifier: descriptor.bundleIdentifier,
                    processID: processID,
                    windowIndex: index,
                    title: title,
                    windowNumber: windowID,
                    windowFrame: windowID.flatMap { windowFrame(forWindowNumber: $0, processID: processID) },
                    tty: tty.isEmpty ? nil : tty,
                    currentPath: currentPath(forTTY: tty)
                )
            }
    }

    private func fetchWindowsUsingAccessibility(for descriptor: TerminalAppDescriptor, processID: pid_t) -> [TerminalWindow] {
        let appElement = AXUIElementCreateApplication(processID)
        var rawWindows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &rawWindows)

        guard result == .success, let windows = rawWindows as? [AXUIElement] else {
            return []
        }

        return windows.compactMap { window -> TerminalWindow? in
            var rawRole: CFTypeRef?
            var rawSubrole: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &rawRole)
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &rawSubrole)

            let role = rawRole as? String
            let subrole = rawSubrole as? String
            guard role == kAXWindowRole as String else { return nil }
            guard subrole == nil || subrole == kAXStandardWindowSubrole as String else { return nil }

            var rawWindowNumber: CFTypeRef?
            var rawTitle: CFTypeRef?
            AXUIElementCopyAttributeValue(window, "AXWindowNumber" as CFString, &rawWindowNumber)
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &rawTitle)
            let title = rawTitle as? String ?? descriptor.displayName

            var rawMinimized: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &rawMinimized)
            let isMinimized = rawMinimized as? Bool ?? false

            return TerminalWindow(
                appName: descriptor.displayName,
                    bundleIdentifier: descriptor.bundleIdentifier,
                    processID: processID,
                    windowIndex: isMinimized ? 10_000 : 0,
                    title: title,
                    windowNumber: intValue(from: rawWindowNumber),
                    windowFrame: axFrame(for: window),
                    tty: nil,
                    currentPath: nil
                )
        }
        .enumerated()
        .map { offset, terminal in
            TerminalWindow(
                appName: terminal.appName,
                bundleIdentifier: terminal.bundleIdentifier,
                processID: terminal.processID,
                windowIndex: offset + 1,
                title: terminal.title,
                windowNumber: terminal.windowNumber,
                windowFrame: terminal.windowFrame,
                tty: terminal.tty,
                currentPath: terminal.currentPath
            )
        }
    }

    private func fetchWindowsUsingWindowServer(for descriptor: TerminalAppDescriptor, processID: pid_t) -> [TerminalWindow] {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowInfo
            .filter { info in
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t
                let layer = info[kCGWindowLayer as String] as? Int
                let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
                let bounds = info[kCGWindowBounds as String] as? [String: Any]
                let width = bounds?["Width"] as? Double ?? 0
                let height = bounds?["Height"] as? Double ?? 0

                // CGWindowList also returns Terminal-owned helper surfaces such as
                // menu-bar-sized strips and small internal panels. They are not
                // user terminal windows, so keep only reasonably window-sized items.
                return ownerPID == processID && layer == 0 && alpha > 0 && width >= 320 && height >= 200
            }
            .enumerated()
            .compactMap { offset, info -> TerminalWindow? in
                let title = info[kCGWindowName as String] as? String ?? descriptor.displayName
                let number = info[kCGWindowNumber as String] as? Int
                return TerminalWindow(
                    appName: descriptor.displayName,
                    bundleIdentifier: descriptor.bundleIdentifier,
                    processID: processID,
                    windowIndex: offset + 1,
                    title: title,
                    windowNumber: number,
                    windowFrame: number.flatMap { windowFrame(forWindowNumber: $0, processID: processID) },
                    tty: nil,
                    currentPath: nil
                )
            }
    }

    private func windowFrame(forWindowNumber windowNumber: Int, processID: pid_t) -> CGRect? {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        guard let info = windowInfo.first(where: { item in
            (item[kCGWindowNumber as String] as? Int) == windowNumber
            && (item[kCGWindowOwnerPID as String] as? pid_t) == processID
        }), let bounds = info[kCGWindowBounds as String] as? [String: Any] else {
            return nil
        }

        let x = bounds["X"] as? CGFloat ?? 0
        let y = bounds["Y"] as? CGFloat ?? 0
        let width = bounds["Width"] as? CGFloat ?? 0
        let height = bounds["Height"] as? CGFloat ?? 0
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func currentPath(forTTY tty: String) -> String? {
        guard !tty.isEmpty else { return nil }
        let ttyName = tty.replacingOccurrences(of: "/dev/", with: "")
        let command = """
        pid=$(ps -t \(ttyName) -o pid= 2>/dev/null | tail -1 | tr -d ' ')
        [ -n \"$pid\" ] || exit 0
        lsof -a -p \"$pid\" -d cwd -Fn 2>/dev/null | awk 'substr($0,1,1)==\"n\" {print substr($0,2); exit}'
        """
        let output = runShell(command)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    private func deduplicated(_ windows: [TerminalWindow]) -> [TerminalWindow] {
        var seen = Set<String>()
        var output: [TerminalWindow] = []

        for window in windows {
            let normalizedTitle = window.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            let key = window.windowNumber.map { "number:\($0)" } ?? "title:\(window.bundleIdentifier):\(normalizedTitle)"

            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(
                TerminalWindow(
                    appName: window.appName,
                    bundleIdentifier: window.bundleIdentifier,
                    processID: window.processID,
                    windowIndex: output.count + 1,
                    title: window.title,
                    windowNumber: window.windowNumber,
                    windowFrame: window.windowFrame,
                    tty: window.tty,
                    currentPath: window.currentPath
                )
            )
        }

        return output
    }

    private func runAppleScript(_ source: String) -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return "" }
        let result = script.executeAndReturnError(&error)
        if let error {
            NSLog("AppleScript error: %@", error)
        }
        return result.stringValue ?? ""
    }

    private func runShell(_ command: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            NSLog("Shell error: %@", String(describing: error))
            return ""
        }
    }
}

struct TerminalAppDescriptor {
    let displayName: String
    let bundleIdentifier: String
}
