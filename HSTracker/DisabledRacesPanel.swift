import AppKit
import CoreGraphics

// 左上角合并面板：绿色“一键拔线”按钮 + 白色“禁用：种族”。
// 视觉风格与 Bob's Buddy 面板一致。

private let disabledRacesHearthstoneBundleIdentifier = "unity.Blizzard Entertainment.Hearthstone"

private final class TopLeftMergedView: NSView {
    // 与 Bob's Buddy 面板底部的状态栏同高、同风格（BobsBuddyPanelView.statusBar）：
    // 文案最小高度 20 + 上下各 5 的内边距 = 30，背景 #141617、圆角 3、
    // 字号 14、白色文字——只有“一键拔线”用绿色。
    // Bob's Buddy 画在 RootOverlayView 的 1080 参考画布上按窗口高度等比缩放，
    // 这里沿用同一套换算，所以任何窗口尺寸下两者高度都一致。
    static let referenceHeight: CGFloat = 30
    static let referenceCanvasHeight: CGFloat = 1080

    private static let referenceHorizontalPadding: CGFloat = 5
    private static let referenceButtonGap: CGFloat = 8
    private static let referenceButtonMinWidth: CGFloat = 78
    private static let referenceButtonHeight: CGFloat = 20
    private static let referenceCornerRadius: CGFloat = 3
    private static let referenceFontSize: CGFloat = 14

    /// RootOverlayView 使用的缩放比，参考高度 1080。
    static func scale(hearthstoneHeight: CGFloat) -> CGFloat {
        guard hearthstoneHeight > 0 else { return 1 }
        return hearthstoneHeight / referenceCanvasHeight
    }

    /// 面板高度直接取 Bob's Buddy 状态栏在当前缩放下的高度。
    static func height(hearthstoneHeight: CGFloat) -> CGFloat {
        max((referenceHeight * scale(hearthstoneHeight: hearthstoneHeight)).rounded(), 1)
    }

    /// 视图按自身高度反推缩放比，保证内容与面板一起缩放。
    private var scale: CGFloat {
        max(bounds.height / Self.referenceHeight, 0.1)
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

    private let overlay = NSPanel(
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

        let races = (game.unavailableRaces ?? []).sorted {
            String.localizedString($0.rawValue, comment: "tribe")
                < String.localizedString($1.rawValue, comment: "tribe")
        }
        contentView.races = races

        // 与 Bob's Buddy 状态栏同高：用 RootOverlayView 的 1080 参考做等比换算，
        // 并把内边距、字号一起按同一比例缩放。
        let scale = TopLeftMergedView.scale(hearthstoneHeight: gameFrame.height)
        let width = TopLeftMergedView.preferredWidth(
            races: races,
            buttonTitle: contentView.buttonTitle,
            scale: scale
        )
        let height = TopLeftMergedView.height(hearthstoneHeight: gameFrame.height)
        // 吸顶：贴到炉石窗口真正的上边缘，只保留左右留白。
        let top = hearthstoneWindowTop(gameFrame: gameFrame)
        logState("shown: frame=\(gameFrame) top=\(top) height=\(height) "
            + "screens=\(NSScreen.screens.map { $0.frame }) races=\(races.map { $0.rawValue })")
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
