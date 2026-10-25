import AppKit
import WebKit

/// Uses a separate, app-owned WebKit login session. Never reads another app's
/// cookies, Keychain items, conversation files, or OAuth tokens.
final class ClaudeUsageClient: NSObject, WKNavigationDelegate, WKUIDelegate {
    var onConnectionChanged: (() -> Void)?
    private var webView: WKWebView?
    private var window: NSWindow?
    private var statusLabel: NSTextField?
    private var pending: (id: UUID, completion: (Result<UsageSnapshot, Error>) -> Void)?
    private var evaluating: UUID?
    private var cooldownUntil = Date.distantPast
    private var needsConnection = false
    private var choosingOrganization = false
    private var disconnecting = false
    private let organizationKey = "claudeUsageOrganizationID"

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        webView = view
        view.load(URLRequest(url: URL(string: "https://claude.ai/settings/usage")!))
        return view
    }

    func connect() {
        guard !disconnecting else { return }
        let view = ensureWebView()
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                 backing: .buffered, defer: false)
            panel.title = "连接 Claude 用量"
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 760, height: 560)
            let content = NSView()
            let status = NSTextField(wrappingLabelWithString: "请在下方登录 Claude，然后点击“读取额度”。登录状态由本机 WebKit 保存。")
            let retry = NSButton(title: "读取额度", target: self, action: #selector(recheck))
            for item in [status, retry, view] as [NSView] {
                item.translatesAutoresizingMaskIntoConstraints = false
                content.addSubview(item)
            }
            NSLayoutConstraint.activate([
                status.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
                status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
                status.trailingAnchor.constraint(lessThanOrEqualTo: retry.leadingAnchor, constant: -12),
                retry.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
                retry.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
                view.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 16),
                view.topAnchor.constraint(greaterThanOrEqualTo: retry.bottomAnchor, constant: 12),
                view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: content.bottomAnchor)
            ])
            statusLabel = status
            panel.contentView = content
            panel.center()
            window = panel
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func recheck() {
        guard !disconnecting else { return }
        needsConnection = false
        statusLabel?.stringValue = "正在读取 Claude 订阅额度…"
        onConnectionChanged?()
    }

    func disconnect(completion: @escaping () -> Void) {
        guard !disconnecting else { return }
        disconnecting = true
        needsConnection = true
        if let pending { finish(pending.id, .failure(ClaudeUsageError.notConnected)) }
        webView?.stopLoading()
        window?.close()
        window = nil
        webView = nil
        statusLabel = nil
        UserDefaults.standard.removeObject(forKey: organizationKey)
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                               modifiedSince: .distantPast) { [weak self] in
            self?.disconnecting = false
            completion()
        }
    }

    func fetch(completion: @escaping (Result<UsageSnapshot, Error>) -> Void) {
        guard !disconnecting else { completion(.failure(ClaudeUsageError.notConnected)); return }
        guard pending == nil else { completion(.failure(ClaudeUsageError.requestFailed)); return }
        guard Date() >= cooldownUntil else { completion(.failure(ClaudeUsageError.http(429))); return }
        guard !needsConnection else { completion(.failure(ClaudeUsageError.notConnected)); return }
        let id = UUID()
        pending = (id, completion)
        let view = ensureWebView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.finish(id, .failure(ClaudeUsageError.timeout))
        }
        if !view.isLoading { readUsage(id) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let pending { readUsage(pending.id) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if let pending { finish(pending.id, .failure(ClaudeUsageError.requestFailed)) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if let pending { finish(pending.id, .failure(ClaudeUsageError.requestFailed)) }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            handleMainFrameNavigation(navigationAction, in: webView)
        }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(navigationAction.request.url?.scheme == "https" ? .allow : .cancel)
            return
        }
        guard let url = navigationAction.request.url,
              ClaudeNavigationPolicy.allowsEmbeddedNavigation(to: url) else {
            handleMainFrameNavigation(navigationAction, in: nil)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    private func handleMainFrameNavigation(_ action: WKNavigationAction, in view: WKWebView?) {
        guard let url = action.request.url else { return }
        if ClaudeNavigationPolicy.allowsEmbeddedNavigation(to: url) {
            view?.load(action.request)
        } else if action.navigationType == .linkActivated, url.scheme == "https",
                  url.user == nil, url.password == nil {
            NSWorkspace.shared.open(url)
        } else {
            statusLabel?.stringValue = ClaudeUsageError.unsupportedNavigation.localizedDescription
        }
    }

    private func readUsage(_ id: UUID) {
        guard pending?.id == id, evaluating != id, let view = webView else { return }
        guard view.url?.scheme == "https", view.url?.host == "claude.ai" else {
            finish(id, .failure(ClaudeUsageError.notConnected)); return
        }
        evaluating = id
        let organization = UserDefaults.standard.string(forKey: organizationKey) ?? ""
        view.callAsyncJavaScript(Self.requestScript, arguments: ["selectedOrganization": organization],
                                 in: nil, in: .defaultClient) { [weak self] result in
            guard let self, self.pending?.id == id else { return }
            self.evaluating = nil
            guard case .success(let value) = result, let response = value as? [String: Any],
                  let kind = response["kind"] as? String else {
                self.finish(id, .failure(ClaudeUsageError.requestFailed)); return
            }
            switch kind {
            case "usage":
                do {
                    guard let body = response["data"] else { throw ClaudeUsageError.invalidResponse }
                    let snapshot = try ClaudeUsageParser.snapshot(from: body)
                    if let org = response["organization"] as? String, UUID(uuidString: org) != nil {
                        UserDefaults.standard.set(org, forKey: self.organizationKey)
                    }
                    self.finish(id, .success(snapshot))
                } catch { self.finish(id, .failure(error)) }
            case "choose":
                self.finish(id, .failure(ClaudeUsageError.chooseOrganization))
                if let choices = response["organizations"] as? [[String: String]] {
                    self.chooseOrganization(choices)
                }
            case "http":
                let code = (response["status"] as? NSNumber)?.intValue ?? 0
                if code == 401 || code == 403 {
                    self.needsConnection = true
                    self.finish(id, .failure(ClaudeUsageError.notConnected))
                } else {
                    if code == 429 {
                        let retry = (response["retryAfter"] as? NSNumber)?.doubleValue ?? 300
                        self.cooldownUntil = Date().addingTimeInterval(max(300, retry.isFinite ? retry : 300))
                    }
                    self.finish(id, .failure(ClaudeUsageError.http(code)))
                }
            default: self.finish(id, .failure(ClaudeUsageError.invalidResponse))
            }
        }
    }

    private func finish(_ id: UUID, _ result: Result<UsageSnapshot, Error>) {
        guard let request = pending, request.id == id else { return }
        pending = nil
        evaluating = nil
        switch result {
        case .success:
            statusLabel?.stringValue = "已连接。切回 Claude 桌面客户端即可查看额度。"
        case .failure(let error): statusLabel?.stringValue = error.localizedDescription
        }
        request.completion(result)
    }

    private func chooseOrganization(_ choices: [[String: String]]) {
        guard let window, window.isVisible, !choosingOrganization else { return }
        let valid = choices.filter { UUID(uuidString: $0["id"] ?? "") != nil }
        guard !valid.isEmpty else { return }
        choosingOrganization = true
        let alert = NSAlert()
        alert.messageText = "选择 Claude 工作区"
        alert.informativeText = "请选择与你在 Claude 桌面版中使用的账号和工作区相同的一项。"
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        picker.addItems(withTitles: valid.map { $0["name"] ?? $0["id"]! })
        alert.accessoryView = picker
        alert.addButton(withTitle: "连接")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.choosingOrganization = false
            if response == .alertFirstButtonReturn {
                UserDefaults.standard.set(valid[picker.indexOfSelectedItem]["id"], forKey: self.organizationKey)
                self.recheck()
            }
        }
    }

    // The website API is not a public, versioned API; fail closed on schema changes.
    // Only same-origin requests run, and cookies never cross the WebKit boundary.
    static let requestScript = #"""
    if (location.origin !== 'https://claude.ai') return {kind: 'invalid'};
    const request = async path => {
        const response = await fetch(path, {credentials: 'same-origin', cache: 'no-store', redirect: 'error'});
        if (!response.ok) {
            const retry = response.headers.get('Retry-After');
            const seconds = Number(retry);
            const retryAfter = retry && Number.isFinite(seconds) ? seconds : Math.max(0, (Date.parse(retry) - Date.now()) / 1000);
            return {kind: 'http', status: response.status, retryAfter: Number.isFinite(retryAfter) ? retryAfter : 300};
        }
        if (!(response.headers.get('Content-Type') || '').includes('application/json')) {
            return {kind: 'http', status: 401};
        }
        return {kind: 'json', data: await response.json()};
    };
    const organizations = await request('/api/organizations');
    if (organizations.kind !== 'json') return organizations;
    if (!Array.isArray(organizations.data)) return {kind: 'invalid'};
    const valid = organizations.data.filter(org => org && typeof org.uuid === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(org.uuid));
    const organization = valid.find(org => org.uuid === selectedOrganization) || (!selectedOrganization && valid.length === 1 ? valid[0] : null);
    if (!organization) return valid.length ? {kind: 'choose', organizations: valid.map(org => ({id: org.uuid, name: typeof org.name === 'string' ? org.name : org.uuid}))} : {kind: 'http', status: 401};
    const usage = await request('/api/organizations/' + encodeURIComponent(organization.uuid) + '/usage');
    if (usage.kind !== 'json') return usage;
    if (!usage.data || Array.isArray(usage.data) || typeof usage.data !== 'object') return {kind: 'invalid'};
    const pick = value => value == null ? null : {utilization: value.utilization, resets_at: value.resets_at};
    return {kind: 'usage', organization: organization.uuid,
            data: {five_hour: pick(usage.data.five_hour), seven_day: pick(usage.data.seven_day)}};
    """#
}
