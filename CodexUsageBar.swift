import AppKit
import Darwin
import Foundation

private struct UsageWindow: Codable {
    let usedPercent: Int
    let resetsAt: TimeInterval?
}

private struct UsageSnapshot: Codable {
    let fiveHour: UsageWindow
    let weekly: UsageWindow
    let fetchedAt: TimeInterval
}

final class UsageBar: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var displayButton: NSButton!
    private let menu = NSMenu()
    private var timer: Timer?
    private var visibilityTimer: Timer?
    private var lastSnapshot: UsageSnapshot?
    private let queue = DispatchQueue(label: "CodexUsageBar.refresh")
    private let codexURL = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex")
    // Codex and Work share this application identifier, even when named ChatGPT.app.
    private let codexBundleIdentifier = "com.openai.codex"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        displayButton = NSButton(title: "Codex 用量…", target: self, action: #selector(openMenu))
        displayButton.isBordered = false
        displayButton.font = .systemFont(ofSize: 13)
        displayButton.cell?.usesSingleLineMode = true
        displayButton.cell?.lineBreakMode = .byTruncatingTail
        panel.contentView = displayButton
        positionPanel()
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceNotifications.addObserver(
            self,
            selector: #selector(frontmostApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        workspaceNotifications.addObserver(
            self,
            selector: #selector(frontmostApplicationChanged(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil
        )
        updatePanelVisibility()
        // Launching an accessory app can temporarily leave no frontmost app.
        // Reconcile periodically as well as on notifications so that a launch or
        // activation handoff cannot leave the panel hidden indefinitely.
        let visibilityTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updatePanelVisibility()
        }
        self.visibilityTimer = visibilityTimer
        RunLoop.main.add(visibilityTimer, forMode: .common)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(positionPanel),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        if let data = UserDefaults.standard.data(forKey: "lastUsageSnapshot"),
           let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data),
           Date().timeIntervalSince1970 - snapshot.fetchedAt < 86_400 {
            lastSnapshot = snapshot
            show(snapshot, stale: true, error: nil)
        }
        refreshNow()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refreshNow() }
    }

    @objc private func frontmostApplicationChanged(_ notification: Notification) {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if notification.name == NSWorkspace.didDeactivateApplicationNotification,
           application?.bundleIdentifier == codexBundleIdentifier {
            // Hide immediately during the handoff to another application's menu bar.
            menu.cancelTracking()
            panel.orderOut(nil)
        }
        // Read the current state after the activation handoff, rather than trusting
        // an event for an app that may already have lost focus again.
        DispatchQueue.main.async { [weak self] in self?.updatePanelVisibility() }
    }

    private func updatePanelVisibility() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier == codexBundleIdentifier,
              !application.isHidden else {
            if panel.isVisible {
                menu.cancelTracking()
                panel.orderOut(nil)
            }
            return
        }
        positionPanel()
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    @objc private func refreshNow() {
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.readUsage()
            DispatchQueue.main.async {
                switch result {
                case .success(let snapshot):
                    self.lastSnapshot = snapshot
                    if let data = try? JSONEncoder().encode(snapshot) {
                        UserDefaults.standard.set(data, forKey: "lastUsageSnapshot")
                    }
                    self.show(snapshot, stale: false, error: nil)
                case .failure(let error):
                    if let snapshot = self.lastSnapshot,
                       Date().timeIntervalSince1970 - snapshot.fetchedAt < 86_400 {
                        self.show(snapshot, stale: true, error: error.localizedDescription)
                    } else {
                        self.displayButton.attributedTitle = NSAttributedString(string: "Codex 用量暂不可读")
                        self.displayButton.toolTip = "\(error.localizedDescription) · 每分钟自动重试"
                        self.positionPanel()
                    }
                }
            }
        }
    }

    private func readUsage() -> Result<UsageSnapshot, Error> {
        guard FileManager.default.isExecutableFile(atPath: codexURL.path) else {
            return .failure(NSError(domain: "CodexUsageBar", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到 Codex CLI：\(codexURL.path)"]))
        }
        let process = Process()
        process.executableURL = codexURL
        process.arguments = ["app-server", "--stdio"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failure(error) }

        let writer = input.fileHandleForWriting
        let reader = output.fileHandleForReading
        let fileDescriptor = reader.fileDescriptor
        let flags = fcntl(fileDescriptor, F_GETFL)
        if flags >= 0 { _ = fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK) }
        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            data.append(0x0A)
            try writer.write(contentsOf: data)
        }
        var buffer = Data()
        func readLine(until deadline: Date) throws -> [String: Any] {
            while Date() < deadline {
                if let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer.prefix(upTo: newline)
                    buffer.removeSubrange(...newline)
                    if let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] {
                        return object
                    }
                    continue
                }
                let remaining = max(1, min(20_000, Int(deadline.timeIntervalSinceNow * 1000)))
                var descriptor = pollfd(fd: fileDescriptor, events: Int16(POLLIN), revents: 0)
                let ready = Darwin.poll(&descriptor, 1, Int32(remaining))
                if ready == 0 { break }
                if ready < 0 {
                    if errno == EINTR { continue }
                    throw NSError(domain: "CodexUsageBar", code: 4, userInfo: [NSLocalizedDescriptionKey: "读取 Codex 服务失败"])
                }
                var bytes = [UInt8](repeating: 0, count: 8192)
                let count = Darwin.read(fileDescriptor, &bytes, bytes.count)
                if count == 0 {
                    throw NSError(domain: "CodexUsageBar", code: 5, userInfo: [NSLocalizedDescriptionKey: "Codex 服务已退出"])
                }
                if count < 0 {
                    if errno == EAGAIN || errno == EINTR { continue }
                    throw NSError(domain: "CodexUsageBar", code: 4, userInfo: [NSLocalizedDescriptionKey: "读取 Codex 服务失败"])
                }
                buffer.append(contentsOf: bytes.prefix(count))
            }
            throw NSError(domain: "CodexUsageBar", code: 2, userInfo: [NSLocalizedDescriptionKey: "读取 Codex 用量超时"])
        }
        defer { if process.isRunning { process.terminate() } }
        do {
            try send(["jsonrpc":"2.0", "id":1, "method":"initialize", "params":["clientInfo":["name":"codex_usage_bar", "title":"Codex Usage Bar", "version":"1.2.2"], "capabilities":["experimentalApi":true]]])
            let initDeadline = Date().addingTimeInterval(8)
            while true {
                let message = try readLine(until: initDeadline)
                if (message["id"] as? Int) == 1 { break }
            }
            try send(["jsonrpc":"2.0", "method":"initialized", "params":[:] as [String: String]])
            try send(["jsonrpc":"2.0", "id":2, "method":"account/rateLimits/read", "params":["excludeResetCreditDetails":true]])
            let readDeadline = Date().addingTimeInterval(20)
            while true {
                let message = try readLine(until: readDeadline)
                if (message["id"] as? Int) != 2 { continue }
                if let failure = message["error"] as? [String: Any] {
                    let detail = failure["message"] as? String ?? "未知错误"
                    throw NSError(domain: "CodexUsageBar", code: 6, userInfo: [NSLocalizedDescriptionKey: "Codex 服务错误：\(detail)"])
                }
                guard let result = message["result"] as? [String: Any] else {
                    throw NSError(domain: "CodexUsageBar", code: 3, userInfo: [NSLocalizedDescriptionKey: "Codex 没有返回用量数据"])
                }
                let all = result["rateLimitsByLimitId"] as? [String: Any] ?? [:]
                guard let snapshot = (all["codex"] as? [String: Any]) ?? (result["rateLimits"] as? [String: Any]),
                      let first = snapshot["primary"] as? [String: Any],
                      let second = snapshot["secondary"] as? [String: Any] else {
                    throw NSError(domain: "CodexUsageBar", code: 3, userInfo: [NSLocalizedDescriptionKey: "Codex 没有返回 5 小时和周用量"])
                }
                let firstDuration = first["windowDurationMins"] as? Int ?? 300
                let secondDuration = second["windowDurationMins"] as? Int ?? 10080
                let fiveHour = firstDuration <= secondDuration ? first : second
                let weekly = firstDuration > secondDuration ? first : second
                func window(_ value: [String: Any]) -> UsageWindow? {
                    guard let used = value["usedPercent"] as? Int else { return nil }
                    let reset = (value["resetsAt"] as? NSNumber)?.doubleValue
                    return UsageWindow(usedPercent: used, resetsAt: reset)
                }
                guard let fiveHourWindow = window(fiveHour), let weeklyWindow = window(weekly) else {
                    throw NSError(domain: "CodexUsageBar", code: 7, userInfo: [NSLocalizedDescriptionKey: "Codex 用量格式无法识别"])
                }
                return .success(UsageSnapshot(fiveHour: fiveHourWindow, weekly: weeklyWindow, fetchedAt: Date().timeIntervalSince1970))
            }
        } catch { return .failure(error) }
    }

    private func show(_ snapshot: UsageSnapshot, stale: Bool, error: String?) {
        let title = NSMutableAttributedString(string: "5小时 ")
        appendWindow(snapshot.fiveHour, weekly: false, stale: stale, to: title)
        title.append(NSAttributedString(string: " | 周 "))
        appendWindow(snapshot.weekly, weekly: true, stale: stale, to: title)
        displayButton.attributedTitle = title
        if stale {
            let time = Date(timeIntervalSince1970: snapshot.fetchedAt).formatted(date: .omitted, time: .shortened)
            displayButton.toolTip = "上次成功读取：\(time) · \(error ?? "正在刷新")"
        } else {
            displayButton.toolTip = "Codex 剩余额度 · 每分钟自动刷新"
        }
        positionPanel()
    }

    @objc private func positionPanel() {
        guard let screen = NSScreen.screens.first else { return }
        let preferredWidth = displayButton.fittingSize.width + 16
        let frame: NSRect
        if screen.safeAreaInsets.top > 0,
           let leftArea = screen.auxiliaryTopLeftArea,
           leftArea.width > 16, leftArea.height > 0 {
            // Use the display's actual camera housing geometry rather than a model list.
            // Keep the entire window to its left, including when the title grows.
            let gap: CGFloat = 8
            let width = min(preferredWidth, leftArea.width - 2 * gap)
            frame = NSRect(
                x: leftArea.maxX - gap - width,
                y: leftArea.minY,
                width: width,
                height: leftArea.height
            )
        } else {
            let menuBarHeight = max(24, min(34, screen.frame.maxY - screen.visibleFrame.maxY))
            let width = min(preferredWidth, screen.frame.width - 24)
            frame = NSRect(
                x: screen.frame.midX - width / 2,
                y: screen.frame.maxY - screen.safeAreaInsets.top - menuBarHeight,
                width: width,
                height: menuBarHeight
            )
        }
        panel.setFrame(frame, display: true)
        displayButton.frame = NSRect(origin: .zero, size: frame.size)
    }

    @objc private func openMenu() {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: displayButton)
    }

    private func appendWindow(_ value: UsageWindow, weekly: Bool, stale: Bool, to title: NSMutableAttributedString) {
        if stale, let reset = value.resetsAt, reset <= Date().timeIntervalSince1970 {
            title.append(NSAttributedString(string: "待更新"))
            return
        }
        let remaining = max(0, min(100, 100 - value.usedPercent))
        let percentage = "\(stale ? "~" : "")\(remaining)%"
        title.append(NSAttributedString(string: percentage, attributes: [.foregroundColor: NSColor.systemGreen]))
        guard let timestamp = value.resetsAt else {
            title.append(NSAttributedString(string: "-重置时间未知"))
            return
        }
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = weekly ? "M/d HH:mm" : "HH:mm"
        title.append(NSAttributedString(string: "-\(formatter.string(from: date))"))
    }

    @objc private func quit() { NSApp.terminate(nil) }

}

@main
enum CodexUsageBarMain {
    private static let delegate = UsageBar()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

