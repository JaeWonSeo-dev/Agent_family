import SwiftUI
import AppKit
import CoreGraphics
import ApplicationServices

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
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)

        let rootView = FloatingTerminalOverlay()
            .environmentObject(store)
            .frame(width: 320, height: 190)

        let hostingView = TransparentHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 190)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let overlayWindow = FloatingOverlayWindow(
            contentRect: NSRect(x: 120, y: 720, width: 320, height: 190),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        overlayWindow.title = "Agent Family"
        overlayWindow.level = .floating
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.hasShadow = false
        overlayWindow.isMovableByWindowBackground = true
        overlayWindow.isReleasedWhenClosed = false
        overlayWindow.minSize = NSSize(width: 320, height: 190)
        overlayWindow.maxSize = NSSize(width: 320, height: 190)
        overlayWindow.contentView = hostingView
        OverlayWindowRegistry.shared.window = overlayWindow
        overlayWindow.makeKeyAndOrderFront(nil)

        self.window = overlayWindow
        store.startAutoRefresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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

final class FloatingOverlayWindow: NSWindow {
    private var scrollAccumulator: CGFloat = 0
    private let scrollThreshold: CGFloat = 18

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func scrollWheel(with event: NSEvent) {
        scrollAccumulator += event.scrollingDeltaY
        guard abs(scrollAccumulator) >= scrollThreshold else { return }
        NotificationCenter.default.post(name: .agentFamilyScrollWheel, object: scrollAccumulator)
        scrollAccumulator = 0
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
    @State private var isHovering = false
    @State private var selectedIndex = 0

    var body: some View {
        ZStack {
            Color.clear

            if store.terminals.isEmpty {
                emptyState
            } else {
                TerminalCarousel(
                    terminals: store.terminals,
                    selectedIndex: $selectedIndex,
                    onActivate: store.activate
                )
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }

        }
        .background(.clear)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentFamilyScrollWheel)) { notification in
            guard let deltaY = notification.object as? CGFloat else { return }
            stepSelection(deltaY: deltaY)
        }
        .onChange(of: store.terminals.count) { _, count in
            selectedIndex = min(selectedIndex, max(0, count - 1))
        }
        .contextMenu {
            Button("새로고침") { store.refresh() }
            Button("Agent Family 종료") { NSApplication.shared.terminate(nil) }
        }
    }

    private func stepSelection(deltaY: CGFloat) {
        guard !store.terminals.isEmpty else { return }
        let step = deltaY > 0 ? 1 : -1
        selectedIndex = min(max(selectedIndex + step, 0), store.terminals.count - 1)
    }

    private var emptyState: some View {
        Image(systemName: "terminal")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(.green)
            .frame(width: 58, height: 58)
            .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
            .help("감지된 터미널 없음 · 우클릭으로 새로고침")
    }
}

struct TerminalCarousel: View {
    let terminals: [TerminalWindow]
    @Binding var selectedIndex: Int
    let onActivate: (TerminalWindow) -> Void

    private let itemWidth: CGFloat = 82

    var body: some View {
        GeometryReader { proxy in
            let centerOffset = proxy.size.width / 2 - itemWidth / 2
            let selected = terminals[min(selectedIndex, terminals.count - 1)]

            ZStack(alignment: .center) {
                HStack(spacing: 10) {
                    ForEach(Array(terminals.enumerated()), id: \.element.id) { index, terminal in
                        FloatingTerminalIcon(
                            terminal: terminal,
                            isSelected: index == selectedIndex
                        ) {
                            selectedIndex = index
                            onActivate(terminal)
                        }
                        .frame(width: itemWidth)
                        .scaleEffect(index == selectedIndex ? 1.12 : 0.86)
                        .opacity(index == selectedIndex ? 1.0 : 0.46)
                    }
                }
                .offset(x: centerOffset - CGFloat(selectedIndex) * (itemWidth + 10))
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selectedIndex)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                VStack {
                    TerminalSpeechBubble(text: selected.displayPath)
                        .offset(y: -54)
                    Spacer()
                }
                .allowsHitTesting(false)
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

struct FloatingTerminalIcon: View {
    let terminal: TerminalWindow
    var isSelected = true
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: terminal.iconSystemName)
                    .font(.system(size: isSelected ? 30 : 25, weight: .semibold))
                    .foregroundStyle(terminal.tint)
                    .frame(width: 58, height: 58)
                    .background(.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(.white.opacity(0.20), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(isSelected ? 0.36 : 0.18), radius: isSelected ? 12 : 6, x: 0, y: 6)

                Text("\(terminal.windowIndex)")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(terminal.tint, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                    .offset(x: 3, y: 3)
            }
            .frame(width: 68, height: 68)
        }
        .buttonStyle(.plain)
        .help("\(terminal.appName): \(terminal.title.isEmpty ? "Untitled" : terminal.title)")
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
        if raiseUsingAccessibility(terminal) {
            refresh()
            return
        }

        if terminal.bundleIdentifier == "com.apple.Terminal" {
            activateTerminalUsingAppleScript(terminal)
            refresh()
            return
        }

        let escapedTitle = terminal.title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "iTerm2"
            try
                select window \(terminal.windowIndex)
            on error
                try
                    repeat with w in windows
                        if name of w is "\(escapedTitle)" then
                            select w
                            exit repeat
                        end if
                    end repeat
                end try
            end try
            activate
            delay 0.05
            try
                select window \(terminal.windowIndex)
            end try
        end tell
        """

        _ = runAppleScript(script)
        refresh()
    }

    private func activateTerminalUsingAppleScript(_ terminal: TerminalWindow) {
        let script: String
        if let windowNumber = terminal.windowNumber {
            script = """
            tell application "Terminal"
                set targetWindow to missing value
                repeat with w in windows
                    if id of w is \(windowNumber) then
                        set targetWindow to w
                    end if
                end repeat

                if targetWindow is not missing value then
                    repeat with w in windows
                        if id of w is not \(windowNumber) then
                            try
                                set miniaturized of w to true
                            end try
                        end if
                    end repeat
                    set miniaturized of targetWindow to false
                    set visible of targetWindow to true
                    set index of targetWindow to 1
                end if
            end tell
            """
        } else {
            script = """
            tell application "Terminal"
                set targetWindow to window \(terminal.windowIndex)
                set targetID to id of targetWindow
                repeat with w in windows
                    if id of w is not targetID then
                        try
                            set miniaturized of w to true
                        end try
                    end if
                end repeat
                set miniaturized of targetWindow to false
                set visible of targetWindow to true
                set index of targetWindow to 1
            end tell
            """
        }
        _ = runAppleScript(script)
    }

    private func raiseUsingAccessibility(_ terminal: TerminalWindow) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let appElement = AXUIElementCreateApplication(terminal.processID)
        var rawWindows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &rawWindows)
        guard result == .success, let windows = rawWindows as? [AXUIElement] else {
            return false
        }

        let candidates = windows.compactMap { window -> AXWindowCandidate? in
            axWindowCandidate(from: window)
        }

        let targetWindow: AXUIElement?
        if terminal.bundleIdentifier == "com.apple.Terminal", let targetFrame = terminal.windowFrame {
            targetWindow = candidates
                .min { lhs, rhs in
                    frameDistance(lhs.frame, targetFrame) < frameDistance(rhs.frame, targetFrame)
                }?
                .element
        } else {
            let normalizedTargetTitle = normalizeTitle(terminal.title)
            let exactMatch = candidates.first { candidate in
                candidate.title == normalizedTargetTitle
            }?.element

            let indexedMatch: AXUIElement? = {
                guard terminal.windowIndex > 0, terminal.windowIndex <= candidates.count else { return nil }
                return candidates[terminal.windowIndex - 1].element
            }()
            targetWindow = exactMatch ?? indexedMatch
        }

        guard let targetWindow else { return false }

        if terminal.bundleIdentifier == "com.apple.Terminal" {
            for candidate in candidates where !CFEqual(candidate.element, targetWindow) {
                AXUIElementSetAttributeValue(candidate.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            }
        }

        AXUIElementSetAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(targetWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        let raiseResult = AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)

        if terminal.bundleIdentifier == "com.apple.Terminal" {
            for candidate in candidates where !CFEqual(candidate.element, targetWindow) {
                AXUIElementSetAttributeValue(candidate.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            }
            AXUIElementSetAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementSetAttributeValue(targetWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            _ = AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
        }

        return raiseResult == .success
    }

    private struct AXWindowCandidate {
        let element: AXUIElement
        let title: String
        let frame: CGRect
    }

    private func axWindowCandidate(from window: AXUIElement) -> AXWindowCandidate? {
        var rawRole: CFTypeRef?
        var rawSubrole: CFTypeRef?
        var rawTitle: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &rawRole)
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &rawSubrole)
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &rawTitle)

        let role = rawRole as? String
        let subrole = rawSubrole as? String
        guard role == kAXWindowRole as String else { return nil }
        guard subrole == nil || subrole == kAXStandardWindowSubrole as String else { return nil }
        guard let frame = axFrame(for: window) else { return nil }

        return AXWindowCandidate(
            element: window,
            title: normalizeTitle(rawTitle as? String ?? ""),
            frame: frame
        )
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

    private func fetchWindows(for descriptor: TerminalAppDescriptor, processID: pid_t) -> [TerminalWindow] {
        let appleScriptWindows = fetchWindowsUsingAppleScript(for: descriptor, processID: processID)
        if !appleScriptWindows.isEmpty {
            return appleScriptWindows
        }

        let accessibilityWindows = deduplicated(fetchWindowsUsingAccessibility(for: descriptor, processID: processID))
        if !accessibilityWindows.isEmpty {
            return accessibilityWindows
        }

        return deduplicated(fetchWindowsUsingWindowServer(for: descriptor, processID: processID))
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

            var rawTitle: CFTypeRef?
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
                windowNumber: nil,
                windowFrame: nil,
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
