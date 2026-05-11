import AppKit

enum AppearanceMode { case normal, urgent, urgentFast, live }

final class StatusItemManager: NSObject {

    private let statusItem: NSStatusItem
    /// Hosts the SF Symbol so we can drive `addSymbolEffect`. NSStatusItem's
    /// own `button.image` is rendered cell-side and doesn't support symbol
    /// effects — we set it to a transparent placeholder of the same size so
    /// the title still has a leading inset, and overlay this view on top.
    private let iconView: NSImageView
    private let joinItem: NSMenuItem
    private let skipItem: NSMenuItem
    private let upcomingHeader: NSMenuItem
    private var upcomingRows: [NSMenuItem] = []
    private var upcomingSeparator: NSMenuItem?
    private var joinURL: URL?
    private var mode: AppearanceMode = .normal

    var onRefresh: (() -> Void)?
    var onOpenCalendar: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    /// Called with the new state (`true` = mute the next sound, `false` = un-mute).
    var onSkipToggled: ((Bool) -> Void)?

    private static let urgentBackground = NSColor(
        red:   0xFF / 255.0,
        green: 0x3B / 255.0,
        blue:  0x48 / 255.0,
        alpha: 1.0)

    /// Menu-bar font with monospaced digits — keeps the time column from jittering.
    private static let monoFont: NSFont = {
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }()

    /// Title is truncated to this many characters in the menu-bar item.
    /// Dropdown menu entries (e.g. "Join …") show the full title.
    private static let titleCharCap = 20

    private static let iconPointSize: CGFloat = 13
    /// Slightly bigger than the symbol's typeface size so the symbol's
    /// natural bounding box (which exceeds its glyph height) fits.
    private static let iconViewSize: CGFloat = 18

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let cfg = NSImage.SymbolConfiguration(pointSize: Self.iconPointSize, weight: .regular)
        let symbol = NSImage(
            systemSymbolName: "antenna.radiowaves.left.and.right",
            accessibilityDescription: "Dramatic Events")?
            .withSymbolConfiguration(cfg)

        iconView = NSImageView(image: symbol ?? NSImage())
        iconView.symbolConfiguration = cfg
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .labelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        joinItem = NSMenuItem(title: "Join", action: nil, keyEquivalent: "j")
        skipItem = NSMenuItem(title: "Mute next event", action: nil, keyEquivalent: "")
        upcomingHeader = NSMenuItem(title: "Upcoming", action: nil, keyEquivalent: "")
        super.init()
        joinItem.target = self
        joinItem.action = #selector(joinAction)
        joinItem.isHidden = true
        skipItem.target = self
        skipItem.action = #selector(skipAction)
        skipItem.isHidden = true
        upcomingHeader.isEnabled = false
        configureMenu()
        installIconView()
        applyChrome()

        // Showup on app open — animate the icon dropping into place.
        if #available(macOS 14.0, *) {
            iconView.addSymbolEffect(.appear.down.byLayer, options: .nonRepeating)
        }
    }

    // MARK: – Icon hosting

    private func installIconView() {
        guard let button = statusItem.button else { return }

        // Reserve horizontal space inside the button for the icon area. The
        // image itself is fully transparent, so only `iconView` is visible.
        let placeholder = NSImage(size: NSSize(width: Self.iconViewSize,
                                               height: Self.iconViewSize),
                                  flipped: false) { _ in true }
        button.image = placeholder
        button.imagePosition = .imageLeft

        button.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: Self.iconViewSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconViewSize),
            iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            iconView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4)
        ])
    }

    // MARK: – Visuals

    private func applyChrome() {
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        let hot = (mode != .normal)
        button.layer?.cornerRadius   = hot ? 4 : 0
        button.layer?.backgroundColor = hot
            ? Self.urgentBackground.cgColor
            : NSColor.clear.cgColor

        iconView.contentTintColor = hot ? .white : .labelColor
    }

    /// Switch between normal / urgent (slow red pulse) / urgentFast (fast red
    /// pulse, used in the final 3 s) / live (solid red, no pulse).
    func setMode(_ newMode: AppearanceMode) {
        guard newMode != mode else { return }
        let old = mode
        mode = newMode
        applyChrome()

        guard let button = statusItem.button else { return }

        // Background pulse on the button layer
        let pulseDuration: Double?
        switch newMode {
        case .urgent:     pulseDuration = 0.9
        case .urgentFast: pulseDuration = 0.35
        case .normal, .live: pulseDuration = nil
        }
        button.layer?.removeAnimation(forKey: "pulse")
        if let duration = pulseDuration {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue       = 1.0
            anim.toValue         = 0.45
            anim.duration        = duration
            anim.autoreverses    = true
            anim.repeatCount     = .infinity
            anim.timingFunction  = CAMediaTimingFunction(name: .easeInEaseOut)
            button.layer?.add(anim, forKey: "pulse")
        } else {
            button.layer?.opacity = 1.0
        }

        // SF Symbol effects on the icon (macOS 14+).
        if #available(macOS 14.0, *) {
            let wasCountingDown = (old == .urgent || old == .urgentFast)
            let isCountingDown  = (newMode == .urgent || newMode == .urgentFast)

            if !wasCountingDown && isCountingDown {
                iconView.addSymbolEffect(
                    .variableColor.iterative.dimInactiveLayers.nonReversing,
                    options: .repeating)
            } else if wasCountingDown && !isCountingDown {
                iconView.removeAllSymbolEffects()
            }

            // Trigger "appear" again when going live.
            if newMode == .live && old != .live {
                iconView.addSymbolEffect(.appear.down.byLayer, options: .nonRepeating)
            }
        }
    }

    /// Plain status string (e.g. "Loading…", "No meetings today"). No truncation.
    func showText(_ text: String) {
        renderTitle(" \(text) ")
    }

    /// Title + suffix. Title is truncated to ~20 characters.
    /// Suffix is preserved in full so the countdown / "is live!" never gets clipped.
    func showStructured(title: String, suffix: String) {
        let cap = Self.titleCharCap
        let displayTitle: String
        if title.count > cap {
            displayTitle = title.prefix(cap - 1)
                                .trimmingCharacters(in: .whitespaces) + "…"
        } else {
            displayTitle = title
        }
        renderTitle(" \(displayTitle)\(suffix) ")
    }

    private func renderTitle(_ composed: String) {
        guard let button = statusItem.button else { return }
        let fg: NSColor = (mode != .normal) ? .white : .labelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            Self.monoFont,
            .foregroundColor: fg
        ]
        button.attributedTitle = NSAttributedString(string: composed, attributes: attrs)
    }

    // MARK: – Menu

    private func configureMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(joinItem)
        menu.addItem(skipItem)
        menu.addItem(.separator())

        menu.addItem(upcomingHeader)
        let sep = NSMenuItem.separator()
        upcomingSeparator = sep
        menu.addItem(sep)
        upcomingHeader.isHidden = true
        sep.isHidden = true

        let refresh = NSMenuItem(title: "Refresh",
                                 action: #selector(refreshAction),
                                 keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let open = NSMenuItem(title: "Open Calendar",
                              action: #selector(openCalendarAction),
                              keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(openSettingsAction),
                                  keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Dramatic Events",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func refreshAction()      { onRefresh?() }
    @objc private func openCalendarAction() { onOpenCalendar?() }
    @objc private func openSettingsAction() { onOpenSettings?() }
    @objc private func joinAction() {
        if let url = joinURL { NSWorkspace.shared.open(url) }
    }
    @objc private func skipAction() {
        skipItem.state = (skipItem.state == .on) ? .off : .on
        onSkipToggled?(skipItem.state == .on)
    }

    func setJoin(label: String?, url: URL?) {
        if let label = label, let url = url {
            joinItem.title = "Join \(label)"
            joinItem.isHidden = false
            joinURL = url
        } else {
            joinItem.title = "Join"
            joinItem.isHidden = true
            joinURL = nil
        }
    }

    /// Configure the "Mute next event" toggle. Pass `nil` for `label` to hide
    /// the item (no upcoming event to skip).
    func setSkip(label: String?, isMuted: Bool) {
        if let label = label {
            skipItem.title = "Mute next: \(label)"
            skipItem.state = isMuted ? .on : .off
            skipItem.isHidden = false
        } else {
            skipItem.isHidden = true
            skipItem.state = .off
        }
    }

    /// Update the "Upcoming" section. Pass an empty array to hide the section.
    func setUpcoming(_ events: [(title: String, start: Date)]) {
        guard let menu = statusItem.menu else { return }

        // Remove any previous rows we added.
        for row in upcomingRows { menu.removeItem(row) }
        upcomingRows.removeAll()

        if events.isEmpty {
            upcomingHeader.isHidden = true
            upcomingSeparator?.isHidden = true
            return
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none

        // Insert new rows immediately after the header.
        guard let headerIndex = menu.items.firstIndex(of: upcomingHeader) else { return }
        for (offset, event) in events.enumerated() {
            let cap = 35
            let displayTitle = event.title.count > cap
                ? event.title.prefix(cap - 1).trimmingCharacters(in: .whitespaces) + "…"
                : event.title
            let row = NSMenuItem(
                title: "   \(displayTitle) — \(formatter.string(from: event.start))",
                action: nil, keyEquivalent: "")
            row.isEnabled = false
            menu.insertItem(row, at: headerIndex + 1 + offset)
            upcomingRows.append(row)
        }

        upcomingHeader.attributedTitle = NSAttributedString(
            string: "UPCOMING",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ])
        upcomingHeader.isHidden = false
        upcomingSeparator?.isHidden = false
    }
}
