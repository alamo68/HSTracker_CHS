import AppKit
import CoreGraphics

// 左上角合并面板：绿色“一键拔线”按钮 + 白色“禁用：种族”。
// 视觉风格与 Bob's Buddy 面板一致。

private let disabledRacesHearthstoneBundleIdentifier = "unity.Blizzard Entertainment.Hearthstone"

private final class TopLeftMergedView: NSView {
    // 行高 30，与 Bob's Buddy 底部状态栏同高；字号沿用状态栏的 14。
    // 缩放算法和 Bob's Buddy 一样：画在 RootOverlayView 的 1080 参考画布上按窗口高度等比缩放。
    static let referenceHeight: CGFloat = 30
    static let referenceCanvasHeight: CGFloat = 1080

    private static let referenceHorizontalPadding: CGFloat = 5
    private static let referenceButtonGap: CGFloat = 8
    private static let referenceButtonMinWidth: CGFloat = 78
    // 上下不留白：按钮撑满整行，文字在行内垂直居中（顺带整行都可点击）。
    private static let referenceButtonHeight: CGFloat = referenceHeight
    private static let referenceCornerRadius: CGFloat = 3
    private static let referenceFontSize: CGFloat = 14

    /// RootOverlayView 使用的缩放比，参考高度 1080。
    static func scale(hearthstoneHeight: CGFloat) -> CGFloat {
        guard hearthstoneHeight > 0 else { return 1 }
        return hearthstoneHeight / referenceCanvasHeight
    }

    /// 面板高度 = 行高 30 在当前缩放下的高度。
    static func height(hearthstoneHeight: CGFloat) -> CGFloat {
        max((referenceHeight * scale(hearthstoneHeight: hearthstoneHeight)).rounded(), 1)
    }

    /// 当前的画布缩放比，由控制者在定位时写入。
    ///
    /// 以前是从自身高度反推（bounds.height / referenceHeight），参考高度一变字号就会跟着
    /// 翻倍；改成显式传入后，字号只跟 1080 参考画布的缩放走，和 Bob's Buddy 一致。
    var scale: CGFloat = 1 {
        didSet {
            needsDisplay = true
        }
    }

    // 状态栏的文案是 .font(.system(size: 14))，两段文字用同一套字体，
    // 区别只在颜色（见 draw）。
    private static func buttonFont(scale: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: referenceFontSize * scale)
    }

    private static func raceFont(scale: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: referenceFontSize * scale)
    }

    var races: [Race] = [] {
        didSet {
            needsDisplay = true
        }
    }
    var buttonTitle: String = "一键拔线" {
        didSet {
            needsDisplay = true
        }
    }
    var onSkip: (() -> Void)?

    private var buttonRect = NSRect.zero

    static func preferredWidth(races: [Race], buttonTitle: String, scale: CGFloat) -> CGFloat {
        let text = Self.disabledText(races: races)
        let textWidth = (text as NSString)
            .size(withAttributes: [.font: Self.raceFont(scale: scale)]).width
        let buttonTextWidth = (buttonTitle as NSString)
            .size(withAttributes: [.font: Self.buttonFont(scale: scale)]).width
        let resolvedButtonWidth = max(Self.referenceButtonMinWidth * scale, buttonTextWidth + 14 * scale)
        let raw = (Self.referenceHorizontalPadding * 2 + Self.referenceButtonGap) * scale
            + resolvedButtonWidth + textWidth
        return min(max(raw, 190 * scale), 560 * scale)
    }

    private static func disabledText(races: [Race]) -> String {
        let names = races.map { race in
            String.localizedString(race.rawValue, comment: "tribe")
        }
        if names.isEmpty {
            return "禁用：--"
        }
        return "禁用：" + names.joined(separator: "、")
    }

    override func draw(_ dirtyRect: NSRect) {
        let scale = self.scale
        let padding = Self.referenceHorizontalPadding * scale
        let gap = Self.referenceButtonGap * scale
        let radius = Self.referenceCornerRadius * scale

        NSColor(calibratedRed: 0.078, green: 0.086, blue: 0.090, alpha: 0.94).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        let buttonFont = Self.buttonFont(scale: scale)
        let raceFont = Self.raceFont(scale: scale)

        let buttonHeight = Self.referenceButtonHeight * scale
        let buttonTextWidth = (buttonTitle as NSString)
            .size(withAttributes: [.font: buttonFont]).width
        let buttonWidth = max(Self.referenceButtonMinWidth * scale, buttonTextWidth + 14 * scale)
        buttonRect = NSRect(
            x: padding,
            y: (bounds.height - buttonHeight) / 2,
            width: buttonWidth,
            height: buttonHeight
        )

        let buttonParagraph = NSMutableParagraphStyle()
        buttonParagraph.alignment = .center
        let buttonAttributed = NSAttributedString(
            string: buttonTitle,
            attributes: [
                .font: buttonFont,
                .foregroundColor: NSColor(calibratedRed: 0.20, green: 0.90, blue: 0.25, alpha: 1),
                .paragraphStyle: buttonParagraph,
            ]
        )
        let buttonSize = buttonAttributed.size()
        buttonAttributed.draw(at: NSPoint(
            x: buttonRect.midX - buttonSize.width / 2,
            y: buttonRect.midY - buttonSize.height / 2
        ))

        let textParagraph = NSMutableParagraphStyle()
        textParagraph.alignment = .left
        textParagraph.lineBreakMode = .byTruncatingTail
        let text = Self.disabledText(races: races)
        let textAttributed = NSAttributedString(
            string: text,
            attributes: [
                .font: raceFont,
                .foregroundColor: NSColor.white,
                .paragraphStyle: textParagraph,
            ]
        )
        let textRect = NSRect(
            x: buttonRect.maxX + gap,
            y: bounds.midY - textAttributed.size().height / 2,
            width: max(0, bounds.maxX - padding - buttonRect.maxX - gap),
            height: textAttributed.size().height
        )
        textAttributed.draw(in: textRect)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if buttonRect.contains(point) {
            onSkip?()
        }
    }
}

final class DisabledRacesPanelController: NSObject {
    var onSkip: (() -> Void)?

    /// 面板窗口。
    ///
    /// 默认的 `constrainFrameRect(_:to:)` 会把窗口压到菜单栏下方（屏幕的 visibleFrame
    /// 里），于是即便调用方请求的是"上沿贴屏幕顶端"，实际落点也会低一条菜单栏的高度，
    /// 看起来就是没吸顶。这块面板只落在炉石窗口范围内，原样返回请求矩形即可。
    private final class TopLeftPanel: NSPanel {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
            return frameRect
        }
    }

    private let overlay = TopLeftPanel(
        contentRect: NSRect(x: 0, y: 0, width: 260, height: TopLeftMergedView.referenceHeight),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let contentView = TopLeftMergedView()
    private var timer: Timer?
    private var resetFeedbackTask: DispatchWorkItem?
    private var lastStateLog: String?

    override init() {
        super.init()
        overlay.contentView?.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        if let content = overlay.contentView {
            NSLayoutConstraint.activate([
                contentView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                contentView.topAnchor.constraint(equalTo: content.topAnchor),
                contentView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
        }
        contentView.onSkip = { [weak self] in
            self?.onSkip?()
        }

        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.level = .floating
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        overlay.isMovableByWindowBackground = false

        let timer = Timer(timeInterval: 0.3, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    deinit {
        timer?.invalidate()
        resetFeedbackTask?.cancel()
    }

    func showFeedback(_ text: String) {
        contentView.buttonTitle = text
        resetFeedbackTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.contentView.buttonTitle = "一键拔线"
        }
        resetFeedbackTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: task)
    }

    @objc private func poll() {
        // 炉石退出后不会再有日志，currentMode 会停在 gameplay；SizeHelper 的窗口矩形
        // 又是缓存值（只在追踪时 reload），退出后同样不更新。只靠这两者判断，面板会
        // 一直留在左上角，所以这里先实时确认炉石还在运行。
        guard isHearthstoneRunning else {
            logState("hidden: hearthstone not running")
            hideOverlay()
            return
        }

        // 游戏切到后台时收起面板：别的覆盖层都画在 HSTracker 自己的覆盖窗口里，被其它
        // App 盖住自然就看不见了，只有这个面板是 floating 窗口，不主动隐藏会一直浮在最上面。
        guard isHearthstoneOrSelfFrontmost else {
            logState("hidden: hearthstone in background")
            hideOverlay()
            return
        }

        guard let gameFrame = hearthstoneWindowFrame() else {
            logState("hidden: hearthstone window not found")
            hideOverlay()
            return
        }

        // 只在真正进入对局后显示（主菜单、酒馆大厅、排队阶段都隐藏）。
        // 不依赖 isBattlegroundsMatch()：对局中启动/重连时游戏类型可能尚未恢复。
        let mode = AppDelegate.instance().coreManager?.game.currentMode
        guard let game = AppDelegate.instance().coreManager?.game,
              game.currentMode == .gameplay else {
            logState("hidden: mode=\(mode?.rawValue ?? "nil")")
            hideOverlay()
            return
        }

        let races = disabledRaces(of: game).sorted {
            String.localizedString($0.rawValue, comment: "tribe")
                < String.localizedString($1.rawValue, comment: "tribe")
        }
        contentView.races = races

        // 高度 30、字号 14，与 Bob's Buddy 状态栏一致，缩放走 RootOverlayView 的 1080
        // 参考换算。缩放比显式写给视图，字号不跟面板高度走。
        let scale = TopLeftMergedView.scale(hearthstoneHeight: gameFrame.height)
        contentView.scale = scale
        let width = TopLeftMergedView.preferredWidth(
            races: races,
            buttonTitle: contentView.buttonTitle,
            scale: scale
        )
        let height = TopLeftMergedView.height(hearthstoneHeight: gameFrame.height)
        // 吸顶：贴到炉石窗口真正的上边缘，只保留左右留白。
        let top = hearthstoneWindowTop(gameFrame: gameFrame)
        let horizontalMargin = 8 * scale
        overlay.setFrame(
            NSRect(
                x: gameFrame.minX + horizontalMargin,
                y: top - height,
                width: width,
                height: height
            ),
            display: true
        )
        // actual 是窗口服务器最终给到的位置，用来确认请求的吸顶位置有没有被系统改动。
        logState("shown: frame=\(gameFrame) top=\(top) height=\(height) "
            + "actual=\(overlay.frame) screens=\(NSScreen.screens.map { $0.frame }) "
            + "races=\(races.map { $0.rawValue })")
        if !overlay.isVisible {
            overlay.orderFront(nil)
        }
    }

    /// 只在状态发生变化时写日志，避免 0.3s 轮询刷屏。
    private func logState(_ state: String) {
        guard lastStateLog != state else { return }
        lastStateLog = state
        logger.info("[DisabledRacesPanel] \(state)")
    }

    /// 本局被禁用的种族。
    ///
    /// 不能直接用 `game.unavailableRaces`：那里的全集是 `Database.battlegroundRaces`，
    /// 也就是"卡牌数据里出现过的所有种族"，属于历史全集——纳加已经不在酒馆轮换里了，
    /// 它的卡却还留在数据中，于是被误报成"禁用"。
    ///
    /// `BattlegroundsDb` 的 `races` 由 meta period 决定（它自己的注释写着"卡牌数据可能
    /// 带着不在轮换里的种族，所以由 meta period 决定有哪些"），正是"当前有哪些种族"。
    /// 远程配置还没到时会回退到旧的算法。
    private func disabledRaces(of game: Game) -> [Race] {
        let available = game.availableRaces ?? []
        guard let first = available.first, first != .invalid else {
            return []
        }

        let rotation = BattlegroundsDbSingleton.current.races.filter { $0 != .invalid && $0 != .all }
        guard !rotation.isEmpty else {
            return game.unavailableRaces ?? []
        }
        return rotation.filter { !available.contains($0) }
    }

    /// 炉石客户端进程是否还在。
    ///
    /// 这里刻意只用实时查询，不叠加 `game.isRunning`：后者由 NSWorkspace 通知维护，
    /// 本身也可能过期（漏通知时会一直为 false，反而把面板在对局中藏起来），而客户端
    /// 进程是否存在正是面板该不该显示的直接判据。
    private var isHearthstoneRunning: Bool {
        !NSRunningApplication
            .runningApplications(withBundleIdentifier: disabledRacesHearthstoneBundleIdentifier)
            .isEmpty
    }

    /// 前台是炉石，或前台是 HSTracker 自己。
    ///
    /// 把 HSTracker 自己也算作"可以显示"是有意的：之前反馈过点开 HSTracker 界面时
    /// 面板不该消失，所以只有切到第三方 App 才收起。查不到前台应用时按可显示处理，
    /// 宁可多显示也不要误藏。
    private var isHearthstoneOrSelfFrontmost: Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return true
        }
        return frontmost == disabledRacesHearthstoneBundleIdentifier
            || frontmost == Bundle.main.bundleIdentifier
    }

    /// 炉石窗口真正的上边缘。
    ///
    /// SizeHelper 暴露的 `frame` 在非全屏时会减掉标题栏高度（Hearthstone 窗口化时
    /// 有标题栏），直接拿它当“天花板”会让面板停在标题栏下方约 28pt 的位置，看起来
    /// 没有吸顶。`_frame` 是未裁剪的整窗矩形，全屏时两者本来就相等。
    private func hearthstoneWindowTop(gameFrame: NSRect) -> CGFloat {
        let windowFrame = SizeHelper.hearthstoneWindow._frame
        if windowFrame.maxY > 0 && windowFrame.height > 0 {
            return windowFrame.maxY
        }
        // 回退：内容区顶部 + 被减掉的标题栏。
        let titlebar = SizeHelper.hearthstoneWindow.isFullscreen()
            ? 0
            : SizeHelper.HearthstoneWindow.titlebarHeight
        return gameFrame.maxY + titlebar
    }

    /// 优先使用 HSTracker 自身用于定位所有覆盖层的窗口矩形，
    /// 与 Bob's Buddy / 右侧面板同源，保证位置完全一致。
    /// 该值不可用时（例如尚未 reload）再回退到直接查询窗口服务器。
    private func hearthstoneWindowFrame() -> NSRect? {
        let helperFrame = SizeHelper.hearthstoneWindow.frame
        if helperFrame.width > 200 && helperFrame.height > 200 {
            return helperFrame
        }
        return detectedHearthstoneWindowFrame()
    }

    private func detectedHearthstoneWindowFrame() -> NSRect? {
        guard let pid = NSRunningApplication
            .runningApplications(withBundleIdentifier: disabledRacesHearthstoneBundleIdentifier)
            .first?.processIdentifier else {
            return nil
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let candidates = windowInfos.compactMap { info -> CGRect? in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let rawBounds = info[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as! CFDictionary),
                  bounds.width > 200, bounds.height > 200 else {
                return nil
            }
            return bounds
        }

        guard let quartzBounds = candidates.max(by: {
            $0.width * $0.height < $1.width * $1.height
        }), let screen = NSScreen.screens.first(where: {
            $0.frame.minX <= quartzBounds.midX && quartzBounds.midX <= $0.frame.maxX
        }) ?? NSScreen.main else {
            return nil
        }

        return NSRect(
            x: quartzBounds.minX,
            y: screen.frame.maxY - quartzBounds.maxY,
            width: quartzBounds.width,
            height: quartzBounds.height
        )
    }

    private func hideOverlay() {
        if overlay.isVisible {
            overlay.orderOut(nil)
        }
    }
}
