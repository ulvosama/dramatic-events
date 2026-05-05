import AppKit

enum AppearanceMode { case normal, urgent, live }

final class StatusItemManager: NSObject {

    private let statusItem: NSStatusItem
    private let joinItem: NSMenuItem
    private var joinURL: URL?
    private var mode: AppearanceMode = .normal

    var onRefresh: (() -> Void)?
    var onOpenCalendar: (() -> Void)?
    var onOpenSettings: (() -> Void)?

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

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        joinItem = NSMenuItem(title: "Join", action: nil, keyEquivalent: "j")
        super.init()
        joinItem.target = self
        joinItem.action = #selector(joinAction)
        joinItem.isHidden = true
        configureMenu()
        applyChrome()
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

        let cfg = NSImage.SymbolConfiguration(
            pointSize: hot ? 8 : 13,
            weight:    hot ? .bold : .regular)
        let symbolName = hot ? "circle.fill" : "display"
        guard let base = NSImage(systemSymbolName: symbolName,
                                 accessibilityDescription: hot ? "Going live" : "Meeting")?
                                 .withSymbolConfiguration(cfg) else { return }

        if hot {
            let white = NSImage(size: base.size, flipped: false) { rect in
                NSColor.white.set()
                rect.fill()
                base.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
                return true
            }
            white.isTemplate = false
            button.image = white
        } else {
            base.isTemplate = true
            button.image = base
        }
        button.imagePosition = .imageLeft
    }

    /// Switch between normal / urgent (pulsing red) / live (solid red).
    func setMode(_ newMode: AppearanceMode) {
        guard newMode != mode else { return }
        mode = newMode
        applyChrome()

        guard let button = statusItem.button else { return }
        if newMode == .urgent {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue       = 1.0
            anim.toValue         = 0.45
            anim.duration        = 0.9
            anim.autoreverses    = true
            anim.repeatCount     = .infinity
            anim.timingFunction  = CAMediaTimingFunction(name: .easeInEaseOut)
            button.layer?.add(anim, forKey: "pulse")
        } else {
            button.layer?.removeAnimation(forKey: "pulse")
            button.layer?.opacity = 1.0
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
        menu.addItem(.separator())

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
}
