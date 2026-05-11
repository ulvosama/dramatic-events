import AppKit

/// One-screen explainer shown on the very first launch (when Calendar
/// authorization is `.notDetermined`). Reduces "what just opened?" confusion
/// before the system permission dialog appears.
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {

    static let shared = WelcomeWindowController()

    /// Invoked when the user clicks Continue (or closes the window).
    /// Called exactly once. AppDelegate uses it to kick off `requestAccess`.
    var onContinue: (() -> Void)?
    private var didFinish = false

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        win.title = "Welcome"
        win.center()
        win.isReleasedWhenClosed = false
        super.init(window: win)
        win.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        didFinish = false
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the window via the red button counts as "Continue" so we
        // never strand the launch flow waiting for a click that won't happen.
        finish()
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onContinue?()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 32, bottom: 24, right: 32)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        let iconImage = NSImage(named: "AppIcon")
            ?? NSImage(systemSymbolName: "antenna.radiowaves.left.and.right",
                       accessibilityDescription: nil)
        let iconView = NSImageView(image: iconImage ?? NSImage())
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 96),
            iconView.heightAnchor.constraint(equalToConstant: 96)
        ])
        stack.addArrangedSubview(iconView)

        let title = NSTextField(labelWithString: "Welcome to Dramatic Events")
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        title.alignment = .center
        stack.addArrangedSubview(title)

        let body = NSTextField(wrappingLabelWithString:
            "Dramatic Events lives in your menu bar and counts down to your next " +
            "calendar meeting — with a dramatic ten-second sound entrance when it's " +
            "about to start.\n\n" +
            "To do that, it needs read-only access to your Calendar. Your events " +
            "stay on your Mac; nothing is sent anywhere.")
        body.alignment = .center
        body.font = NSFont.systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        body.maximumNumberOfLines = 0
        body.preferredMaxLayoutWidth = 416
        stack.addArrangedSubview(body)

        let cont = NSButton(title: "Continue", target: self, action: #selector(continueTapped))
        cont.bezelStyle = .rounded
        cont.keyEquivalent = "\r"
        cont.controlSize = .large
        stack.addArrangedSubview(cont)
    }

    @objc private func continueTapped() {
        finish()
        window?.close()
    }
}
