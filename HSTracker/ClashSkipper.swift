import AppKit
import CoreGraphics

// MARK: - Clash / mihomo HTTP API client

struct ClashConnection: Decodable {
    let id: String
    let metadata: ClashMetadata
}

struct ClashMetadata: Decodable {
    let processPath: String?
    let host: String?
    let destinationPort: String?
}

struct ClashConnectionsResponse: Decodable {
    let connections: [ClashConnection]
}

struct ClashVersionResponse: Decodable {
    let version: String
}

enum ClashError: LocalizedError {
    case badController
    case httpStatus(Int, String)
    case invalidVersion
    case noGameConnection
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .badController:
            return "external controller 地址无效"
        case .httpStatus(let code, let body):
            let snippet = String(body.prefix(160))
            return "HTTP \(code) \(snippet)"
        case .invalidVersion:
            return "无法解析 /version 返回"
        case .noGameConnection:
            return "未找到炉石对局连接（请确认已进入对局且流量经 Clash）"
        case .transport(let message):
            return message
        }
    }
}

final class ClashClient {
    var controller: String
    var secret: String

    init(controller: String = "127.0.0.1:9097", secret: String = "") {
        self.controller = controller
        self.secret = secret
    }

    func test(completion: @escaping (Result<String, Error>) -> Void) {
        request("/version") { result in
            switch result {
            case .success(let data):
                do {
                    let response = try JSONDecoder().decode(ClashVersionResponse.self, from: data)
                    completion(.success("连接成功，Clash 版本 \(response.version)"))
                } catch {
                    completion(.failure(ClashError.invalidVersion))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func skip(completion: @escaping (Result<String, Error>) -> Void) {
        request("/connections") { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case .success(let data):
                let response: ClashConnectionsResponse
                do {
                    response = try JSONDecoder().decode(ClashConnectionsResponse.self, from: data)
                } catch {
                    completion(.failure(ClashError.httpStatus(200, "connections JSON 解析失败")))
                    return
                }

                let directCandidates = response.connections.filter {
                    self.isHearthstone($0) && ($0.metadata.host ?? "").isEmpty
                }
                guard let target = directCandidates.first(where: { $0.metadata.destinationPort == "1119" })
                        ?? directCandidates.first else {
                    completion(.failure(ClashError.noGameConnection))
                    return
                }

                self.request("/connections/\(target.id)", method: "DELETE") { deleteResult in
                    switch deleteResult {
                    case .success:
                        completion(.success("已断开对局连接 \(target.id.prefix(8))"))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func isHearthstone(_ connection: ClashConnection) -> Bool {
        let processPath = connection.metadata.processPath ?? ""
        return processPath.hasSuffix("Hearthstone.app/Contents/MacOS/Hearthstone")
    }

    private func request(_ path: String, method: String = "GET",
                         completion: @escaping (Result<Data, Error>) -> Void) {
        guard let url = apiURL(path) else {
            completion(.failure(ClashError.badController))
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.timeoutInterval = 6
        if !secret.isEmpty {
            urlRequest.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }

        let task = Self.session.dataTask(with: urlRequest) { data, response, error in
            if let error {
                completion(.failure(ClashError.transport(error.localizedDescription)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(ClashError.transport("非 HTTP 响应")))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
                completion(.failure(ClashError.httpStatus(http.statusCode, body)))
                return
            }
            completion(.success(data ?? Data()))
        }
        task.resume()
    }

    private func apiURL(_ path: String) -> URL? {
        var host = controller.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["http://", "https://"] where host.hasPrefix(prefix) {
            host = String(host.dropFirst(prefix.count))
        }
        guard !host.isEmpty else {
            return nil
        }
        return URL(string: "http://\(host)\(path)")
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 10
        return URLSession(configuration: configuration)
    }()
}

// MARK: - Floating "一键拔线" button

private let clashHearthstoneBundleIdentifier = "unity.Blizzard Entertainment.Hearthstone"

private final class ClashSkipOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ClashSkipButtonView: NSView {
    var title: String = "一键拔线" {
        didSet {
            needsDisplay = true
        }
    }
    var onClick: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var lastMouseLocation: NSPoint?
    private var isDragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        lastMouseLocation = NSEvent.mouseLocation
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = lastMouseLocation else {
            return
        }
        let current = NSEvent.mouseLocation
        if !isDragging {
            let distance = hypot(current.x - start.x, current.y - start.y)
            guard distance > 3 else {
                return
            }
            isDragging = true
            onDragBegan?()
        }
        guard let window else {
            return
        }
        let frame = window.frame
        window.setFrameOrigin(NSPoint(
            x: frame.origin.x + current.x - start.x,
            y: frame.origin.y + current.y - start.y
        ))
        lastMouseLocation = current
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            lastMouseLocation = nil
            isDragging = false
        }
        if isDragging {
            onDragEnded?()
        } else {
            onClick?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: NSColor.white,
            .shadow: shadow,
            .paragraphStyle: paragraph,
        ]
        let attributedTitle = NSAttributedString(string: title, attributes: attributes)
        let textSize = attributedTitle.size()
        attributedTitle.draw(at: NSPoint(
            x: bounds.midX - textSize.width / 2,
            y: bounds.midY - textSize.height / 2
        ))
    }
}

final class ClashSkipFloatingButtonController: NSObject {
    var onSkip: (() -> Void)?

    private let overlay = ClashSkipOverlayPanel(
        contentRect: NSRect(x: 0, y: 0, width: 132, height: 44),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let buttonView = ClashSkipButtonView()
    private var timer: Timer?
    private var resetFeedbackTask: DispatchWorkItem?
    private var autoPositionEnabled = true
    private var followGameWindow = true
    private var offsetRight: CGFloat = 443
    private var offsetTop: CGFloat = 4

    override init() {
        super.init()
        configureOverlay()
        startPolling()
    }

    deinit {
        timer?.invalidate()
        resetFeedbackTask?.cancel()
    }

    func showFeedback(_ text: String) {
        buttonView.title = text
        resetFeedbackTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.buttonView.title = "一键拔线"
        }
        resetFeedbackTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: task)
    }

    private func configureOverlay() {
        buttonView.frame = overlay.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 132, height: 44)
        buttonView.wantsLayer = true
        buttonView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.58).cgColor
        buttonView.layer?.cornerRadius = 10
        buttonView.layer?.borderWidth = 1
        buttonView.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        buttonView.onClick = { [weak self] in
            self?.skipClicked()
        }
        buttonView.onDragBegan = { [weak self] in
            self?.autoPositionEnabled = false
        }
        buttonView.onDragEnded = { [weak self] in
            self?.updateOffsetAfterDrag()
        }

        overlay.contentView?.addSubview(buttonView)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.level = .floating
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        overlay.isMovableByWindowBackground = false
    }

    private func startPolling() {
        let timer = Timer(timeInterval: 0.35, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func poll() {
        guard let activeApp = NSWorkspace.shared.frontmostApplication,
              activeApp.bundleIdentifier == clashHearthstoneBundleIdentifier,
              let windowBounds = gameWindowBounds(pid: activeApp.processIdentifier) else {
            hideOverlay()
            return
        }
        guard let appKitFrame = appKitFrame(fromQuartz: windowBounds) else {
            return
        }
        if followGameWindow && autoPositionEnabled {
            placeOverlay(over: appKitFrame)
        } else if !overlay.isVisible {
            overlay.orderFront(nil)
        }
    }

    @objc private func skipClicked() {
        buttonView.title = "拔线中…"
        onSkip?()
    }

    private func gameWindowBounds(pid: pid_t) -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let candidates = windowInfos.compactMap { info -> CGRect? in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid else {
                return nil
            }
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else {
                return nil
            }
            guard let rawBounds = info[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as! CFDictionary) else {
                return nil
            }
            return bounds.width > 200 && bounds.height > 200 ? bounds : nil
        }

        return candidates.max { lhs, rhs in
            lhs.width * lhs.height < rhs.width * rhs.height
        }
    }

    private func appKitFrame(fromQuartz quartzBounds: CGRect) -> CGRect? {
        guard let screen = NSScreen.screens.first(where: { screen in
            screen.frame.minX <= quartzBounds.midX && quartzBounds.midX <= screen.frame.maxX
        }) ?? NSScreen.main else {
            return nil
        }

        let appKitY = screen.frame.maxY - quartzBounds.maxY
        return CGRect(
            x: quartzBounds.minX,
            y: appKitY,
            width: quartzBounds.width,
            height: quartzBounds.height
        )
    }

    private func placeOverlay(over gameFrame: CGRect) {
        let size = overlay.frame.size
        let x = gameFrame.maxX - size.width - offsetRight
        let topLeftY = gameFrame.maxY - offsetTop

        overlay.setFrameTopLeftPoint(NSPoint(x: x, y: topLeftY))
        if !overlay.isVisible {
            overlay.orderFront(nil)
        }
    }

    private func updateOffsetAfterDrag() {
        autoPositionEnabled = true
        // 拖动结束后按钮固定在松手位置，不再跟随炉石窗口自动纠正。
        followGameWindow = false
    }

    private func hideOverlay() {
        if overlay.isVisible {
            overlay.orderOut(nil)
        }
    }
}

// MARK: - Settings window

final class ClashSkipperSettingsWindowController: NSWindowController {
    var onSave: ((String, String) -> Void)?
    var onTest: ((String, String, @escaping (String) -> Void) -> Void)?

    private let controllerField = NSTextField()
    private let secretField = NSSecureTextField()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let testButton = NSButton(title: "检测", target: nil, action: nil)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 190),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "HSTracker 拔线设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        if let window {
            let mouseLocation = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { screen in
                NSMouseInRect(mouseLocation, screen.frame, false)
            } ?? NSScreen.main
            if let screen {
                let visibleFrame = screen.visibleFrame
                let frame = window.frame
                let origin = NSPoint(
                    x: visibleFrame.midX - frame.width / 2,
                    y: visibleFrame.midY - frame.height / 2
                )
                window.setFrameOrigin(origin)
            }
        }
        super.showWindow(sender)
    }

    func setValues(controller: String, secret: String) {
        controllerField.stringValue = controller
        secretField.stringValue = secret
        statusLabel.stringValue = ""
    }

    private func buildUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let controllerLabel = NSTextField(labelWithString: "External Controller")
        controllerLabel.alignment = .right
        controllerField.placeholderString = "127.0.0.1:9097"
        controllerField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        let secretLabel = NSTextField(labelWithString: "Secret")
        secretLabel.alignment = .right
        secretField.placeholderString = "留空则不发送 Authorization"

        let grid = NSGridView(views: [
            [controllerLabel, controllerField],
            [secretLabel, secretField],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing

        let hint = NSTextField(wrappingLabelWithString: "读取 Clash /connections 并按 Hearthstone + 端口 1119 匹配对局连接")
        hint.textColor = .secondaryLabelColor
        hint.font = NSFont.systemFont(ofSize: 11)

        testButton.target = self
        testButton.action = #selector(testConnection)

        let saveButton = NSButton(title: "保存", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"

        let buttonRow = NSStackView(views: [testButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let root = NSStackView(views: [grid, hint, statusLabel, buttonRow])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
        ])
    }

    @objc private func save() {
        statusLabel.stringValue = "已保存"
        onSave?(controllerField.stringValue, secretField.stringValue)
    }

    @objc private func testConnection() {
        statusLabel.stringValue = "检测中…"
        testButton.isEnabled = false
        let controller = controllerField.stringValue
        let secret = secretField.stringValue
        onTest?(controller, secret) { [weak self] message in
            DispatchQueue.main.async {
                self?.statusLabel.stringValue = message
                self?.testButton.isEnabled = true
            }
        }
    }
}

// MARK: - Integration controller (menu / Dock menu / feedback)

final class ClashSkipperController: NSObject {
    private enum Keys {
        static let controller = "clash_external_controller"
        static let secret = "clash_secret"
    }

    private let clash = ClashClient()
    private let defaults = UserDefaults.standard
    private var settingsWindow: ClashSkipperSettingsWindowController?
    private var busy = false
    private var menuInstalled = false
    private var dockMenuInstalled = false
    var onFeedback: ((String) -> Void)?

    func setup() {
        migrateFromOldSkipperIfNeeded()
        clash.controller = defaults.string(forKey: Keys.controller) ?? "127.0.0.1:9097"
        clash.secret = defaults.string(forKey: Keys.secret) ?? ""
        installMainMenu()
    }

    func installDockMenu(_ dockMenu: NSMenu) {
        guard !dockMenuInstalled else {
            return
        }
        dockMenuInstalled = true

        dockMenu.addItem(.separator())

        let skipItem = NSMenuItem(title: "一键拔线", action: #selector(doSkip), keyEquivalent: "")
        skipItem.tag = 10
        skipItem.target = self
        dockMenu.addItem(skipItem)

        let settingsItem = NSMenuItem(title: "拔线设置", action: #selector(showSettings), keyEquivalent: "")
        settingsItem.tag = 11
        settingsItem.target = self
        dockMenu.addItem(settingsItem)
    }

    func skipNow() {
        doSkip()
    }

    private func installMainMenu() {
        guard !menuInstalled, let mainMenu = NSApp.mainMenu else {
            return
        }
        menuInstalled = true

        let item = NSMenuItem(title: "拔线", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "拔线")

        let skipItem = NSMenuItem(title: "一键拔线", action: #selector(doSkip), keyEquivalent: "k")
        skipItem.keyEquivalentModifierMask = [.command, .shift]
        skipItem.target = self
        submenu.addItem(skipItem)

        let testItem = NSMenuItem(title: "检测 Clash 连接", action: #selector(doTest), keyEquivalent: "")
        testItem.target = self
        submenu.addItem(testItem)

        submenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置secret…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        submenu.addItem(settingsItem)

        item.submenu = submenu

        let preferredNames = ["Window", "窗口", "Help", "帮助"]
        if let index = mainMenu.items.firstIndex(where: { item in
            preferredNames.contains(item.title)
        }) {
            mainMenu.insertItem(item, at: index)
        } else {
            mainMenu.addItem(item)
        }
    }

    @objc private func doSkip() {
        guard !busy else {
            showFeedback(title: "正在拔线", message: "请稍候…")
            return
        }
        busy = true
        onFeedback?("拔线中…")
        clash.skip { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.busy = false
                switch result {
                case .success(let message):
                    self.onFeedback?("✓ 成功")
                    self.showFeedback(title: "一键拔线", message: message)
                case .failure(let error):
                    self.onFeedback?("✗ 失败")
                    self.showFeedback(title: "拔线失败", message: error.localizedDescription)
                }
            }
        }
    }

    @objc private func doTest() {
        guard !busy else {
            return
        }
        busy = true
        clash.test { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.busy = false
                switch result {
                case .success(let message):
                    self.showFeedback(title: "检测成功", message: message)
                case .failure(let error):
                    self.showFeedback(title: "检测失败", message: error.localizedDescription)
                }
            }
        }
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let controller = ClashSkipperSettingsWindowController()
            controller.onSave = { [weak self] address, secret in
                guard let self else { return }
                self.clash.controller = address
                self.clash.secret = secret
                self.defaults.set(address, forKey: Keys.controller)
                self.defaults.set(secret, forKey: Keys.secret)
            }
            controller.onTest = { address, secret, completion in
                let tester = ClashClient(controller: address, secret: secret)
                tester.test { result in
                    switch result {
                    case .success(let message):
                        completion("✓ " + message)
                    case .failure(let error):
                        completion("✗ " + error.localizedDescription)
                    }
                }
            }
            settingsWindow = controller
        }
        settingsWindow?.setValues(controller: clash.controller, secret: clash.secret)
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showFeedback(title: String, message: String) {
        Toast.show(title: title, message: message, duration: 4)
    }

    private func migrateFromOldSkipperIfNeeded() {
        if defaults.string(forKey: Keys.controller) != nil {
            return
        }
        for domain in ["com.local.SwiftSkipper", "com.z2z63-dev.skipper"] {
            guard let oldDefaults = UserDefaults(suiteName: domain) else {
                continue
            }
            if defaults.string(forKey: Keys.controller) == nil,
               let controller = oldDefaults.string(forKey: "external_controller"),
               !controller.isEmpty {
                defaults.set(controller, forKey: Keys.controller)
            }
            if defaults.string(forKey: Keys.secret) == nil,
               let secret = oldDefaults.string(forKey: "secret") {
                defaults.set(secret, forKey: Keys.secret)
            }
        }
    }
}
