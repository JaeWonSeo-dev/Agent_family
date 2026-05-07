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
            .frame(minWidth: 96, minHeight: 96)

        let hostingView = TransparentHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 260, height: 180)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let overlayWindow = NSWindow(
            contentRect: NSRect(x: 120, y: 720, width: 260, height: 180),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        overlayWindow.title = "Agent Family"
        overlayWindow.level = .floating
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.hasShadow = false
        overlayWindow.isMovableByWindowBackground = false
        overlayWindow.isReleasedWhenClosed = false
        overlayWindow.minSize = NSSize(width: 96, height: 96)
        overlayWindow.contentView = hostingView
        OverlayWindowRegistry.shared.window = overlayWindow
        overlayWindow.makeKeyAndOrderFront(nil)

        self.window = overlayWindow
        requestAccessibilityPermissionIfNeeded()
        store.startAutoRefresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func requestAccessibilityPermissionIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

@MainActor
final class OverlayWindowRegistry {
    static let shared = OverlayWindowRegistry()
    weak var window: NSWindow?
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

    private let columns = [
        GridItem(.adaptive(minimum: 64, maximum: 74), spacing: 12)
    ]

    var body: some View {
        ZStack {
            WindowMoveSurface()

            if store.terminals.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(store.terminals) { terminal in
                        FloatingTerminalIcon(terminal: terminal) {
                            store.activate(terminal)
                        }
                    }
                }
                .padding(10)
            }

        }
        .overlay(alignment: .trailing) {
            WindowResizeHandle(edge: .right)
                .frame(maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            WindowResizeHandle(edge: .bottom)
                .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottomTrailing) {
            WindowResizeHandle(edge: .bottomRight, visible: isHovering)
        }
        .background(.clear)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("새로고침") { store.refresh() }
            Button("Agent Family 종료") { NSApplication.shared.terminate(nil) }
        }
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

struct WindowMoveSurface: View {
    @State private var initialFrame: NSRect?

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        moveWindow(with: value.translation)
                    }
                    .onEnded { _ in
                        initialFrame = nil
                    }
            )
    }

    @MainActor
    private func moveWindow(with translation: CGSize) {
        guard let window = OverlayWindowRegistry.shared.window else { return }
        if initialFrame == nil {
            initialFrame = window.frame
        }
        guard let initialFrame else { return }

        var frame = initialFrame
        frame.origin.x += translation.width
        frame.origin.y -= translation.height
        window.setFrame(frame, display: true)
    }
}

enum ResizeEdge {
    case right
    case bottom
    case bottomRight
}

struct WindowResizeHandle: View {
    let edge: ResizeEdge
    var visible = false
    @State private var initialFrame: NSRect?

    var body: some View {
        handleContent
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onHover { hovering in
                updateCursor(hovering: hovering)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        resizeWindow(with: value.translation)
                    }
                    .onEnded { _ in
                        initialFrame = nil
                    }
            )
    }

    @ViewBuilder
    private var handleContent: some View {
        if visible {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 28, height: 28)
                .background(.black.opacity(0.24), in: Circle())
        } else {
            Color.clear
        }
    }

    private var width: CGFloat? {
        switch edge {
        case .right: return 18
        case .bottom: return nil
        case .bottomRight: return 34
        }
    }

    private var height: CGFloat? {
        switch edge {
        case .right: return nil
        case .bottom: return 18
        case .bottomRight: return 34
        }
    }

    private func updateCursor(hovering: Bool) {
        guard hovering else {
            NSCursor.pop()
            return
        }

        switch edge {
        case .right:
            NSCursor.resizeLeftRight.push()
        case .bottom:
            NSCursor.resizeUpDown.push()
        case .bottomRight:
            NSCursor.resizeLeftRight.push()
        }
    }

    @MainActor
    private func resizeWindow(with translation: CGSize) {
        guard let window = OverlayWindowRegistry.shared.window else { return }

        if initialFrame == nil {
            initialFrame = window.frame
        }
        guard let initialFrame else { return }

        var frame = initialFrame
        let minWidth = window.minSize.width
        let minHeight = window.minSize.height

        switch edge {
        case .right:
            frame.size.width = max(minWidth, initialFrame.width + translation.width)
        case .bottom:
            let newHeight = max(minHeight, initialFrame.height - translation.height)
            frame.origin.y = initialFrame.maxY - newHeight
            frame.size.height = newHeight
        case .bottomRight:
            let newHeight = max(minHeight, initialFrame.height - translation.height)
            frame.size.width = max(minWidth, initialFrame.width + translation.width)
            frame.origin.y = initialFrame.maxY - newHeight
            frame.size.height = newHeight
        }

        window.setFrame(frame, display: true)
    }
}

struct FloatingTerminalIcon: View {
    let terminal: TerminalWindow
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: terminal.iconSystemName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(terminal.tint)
                    .frame(width: 58, height: 58)
                    .background(.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(.white.opacity(0.20), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.30), radius: 10, x: 0, y: 6)

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

        let escapedTitle = terminal.title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script: String

        if terminal.bundleIdentifier == "com.apple.Terminal" {
            if let windowNumber = terminal.windowNumber {
                script = """
                tell application "Terminal"
                    try
                        repeat with w in windows
                            if id of w is \(windowNumber) then
                                set visible of w to true
                                set index of w to 1
                                exit repeat
                            end if
                        end repeat
                    end try
                end tell
                """
            } else {
                script = """
                tell application "Terminal"
                    try
                        set visible of window \(terminal.windowIndex) to true
                        set index of window \(terminal.windowIndex) to 1
                    end try
                end tell
                """
            }
        } else {
            script = """
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
            end tell
            """
        }

        _ = runAppleScript(script)
        refresh()
    }

    private func raiseUsingAccessibility(_ terminal: TerminalWindow) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let appElement = AXUIElementCreateApplication(terminal.processID)
        var rawWindows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &rawWindows)
        guard result == .success, let windows = rawWindows as? [AXUIElement] else {
            return false
        }

        let normalizedTargetTitle = normalizeTitle(terminal.title)
        let candidateWindows = windows.compactMap { window -> (AXUIElement, String)? in
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

            return (window, normalizeTitle(rawTitle as? String ?? ""))
        }

        let exactMatch = candidateWindows.first { _, title in
            title == normalizedTargetTitle
        }?.0

        let indexedMatch: AXUIElement? = {
            guard terminal.windowIndex > 0, terminal.windowIndex <= candidateWindows.count else { return nil }
            return candidateWindows[terminal.windowIndex - 1].0
        }()

        guard let targetWindow = exactMatch ?? indexedMatch else {
            return false
        }

        var minimizedValue: CFTypeRef?
        AXUIElementCopyAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, &minimizedValue)
        if (minimizedValue as? Bool) == true {
            AXUIElementSetAttributeValue(targetWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        let raiseResult = AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
        if raiseResult == .success {
            AXUIElementSetAttributeValue(targetWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            return true
        }
        return false
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
                set output to output & i & tab & windowID & tab & (name of w as text) & linefeed
            end repeat
            return output
        end tell
        """

        return runAppleScript(script)
            .split(separator: "\n")
            .compactMap { line -> TerminalWindow? in
                let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard let indexPart = parts.first, let index = Int(indexPart) else { return nil }
                let windowID = parts.count > 1 ? Int(parts[1]) : nil
                let title = parts.count > 2 ? String(parts[2]) : ""
                return TerminalWindow(
                    appName: descriptor.displayName,
                    bundleIdentifier: descriptor.bundleIdentifier,
                    processID: processID,
                    windowIndex: index,
                    title: title,
                    windowNumber: windowID
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
                windowNumber: nil
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
                windowNumber: terminal.windowNumber
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
                    windowNumber: number
                )
            }
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
                    windowNumber: window.windowNumber
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
}

struct TerminalAppDescriptor {
    let displayName: String
    let bundleIdentifier: String
}
