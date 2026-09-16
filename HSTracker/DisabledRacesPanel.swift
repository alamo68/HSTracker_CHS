import AppKit
import CoreGraphics

// 左上角合并面板：绿色“一键拔线”按钮 + 白色“禁用：种族”。
// 视觉风格与 Bob's Buddy 面板一致。

private let disabledRacesHearthstoneBundleIdentifier = "unity.Blizzard Entertainment.Hearthstone"

private final class TopLeftMergedView: NSView {
    static let panelHeight: CGFloat = 26
    static let horizontalPadding: CGFloat = 8
    static let buttonGap: CGFloat = 8
    static let buttonWidth: CGFloat = 78

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

    private static let buttonFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private static let raceFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    static func preferredWidth(races: [Race], buttonTitle: String) -> CGFloat {
        let text = Self.disabledText(races: races)
        let textWidth = (text as NSString).size(withAttributes: [.font: raceFont]).width
        let buttonTextWidth = (buttonTitle as NSString).size(withAttributes: [.font: buttonFont]).width
        let resolvedButtonWidth = max(Self.buttonWidth, buttonTextWidth + 14)
        let raw = horizontalPadding * 2 + resolvedButtonWidth + buttonGap + textWidth
        return min(max(raw, 190), 560)
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
        let radius: CGFloat = 6
        NSColor(calibratedRed: 0.078, green: 0.086, blue: 0.090, alpha: 0.94).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        let buttonTextWidth = (buttonTitle as NSString)
            .size(withAttributes: [.font: Self.buttonFont]).width
        let buttonWidth = max(Self.buttonWidth, buttonTextWidth + 14)
        buttonRect = NSRect(
            x: Self.horizontalPadding,
            y: (bounds.height - 18) / 2,
            width: buttonWidth,
            height: 18
        )

        let buttonParagraph = NSMutableParagraphStyle()
        buttonParagraph.alignment = .center
        let buttonAttributed = NSAttributedString(
            string: buttonTitle,
            attributes: [
                .font: Self.buttonFont,
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
                .font: Self.raceFont,
                .foregroundColor: NSColor.white,
                .paragraphStyle: textParagraph,
            ]
        )
        let textRect = NSRect(
            x: buttonRect.maxX + Self.buttonGap,
            y: bounds.midY - textAttributed.size().height / 2,
            width: max(0, bounds.maxX - Self.horizontalPadding - buttonRect.maxX - Self.buttonGap),
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
        contentRect: NSRect(x: 0, y: 0, width: 260, height: TopLeftMergedView.panelHeight),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let contentView = TopLeftMergedView()
    private var timer: Timer?
    private var resetFeedbackTask: DispatchWorkItem?

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
            hideOverlay()
            return
        }

        // 只在真正进入对局后显示（主菜单、酒馆大厅、排队阶段都隐藏）。
        // 不依赖 isBattlegroundsMatch()：对局中启动/重连时游戏类型可能尚未恢复。
        guard let game = AppDelegate.instance().coreManager?.game,
              game.currentMode == .gameplay else {
            hideOverlay()
            return
        }

        let races = (game.unavailableRaces ?? []).sorted {
            String.localizedString($0.rawValue, comment: "tribe")
                < String.localizedString($1.rawValue, comment: "tribe")
        }
        contentView.races = races

        let width = TopLeftMergedView.preferredWidth(
            races: races,
            buttonTitle: contentView.buttonTitle
        )
        let height = TopLeftMergedView.panelHeight
        let margin: CGFloat = 8
        overlay.setFrame(
            NSRect(
                x: gameFrame.minX + margin,
                y: gameFrame.maxY - height - margin,
                width: width,
                height: height
            ),
            display: true
        )
        if !overlay.isVisible {
            overlay.orderFront(nil)
        }
    }

    private func hearthstoneWindowFrame() -> NSRect? {
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
