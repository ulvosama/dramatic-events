import AppKit
import AVFoundation
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    static let shared = SettingsWindowController()

    // MARK: – Outlets

    private let fileLabel    = NSTextField(labelWithString: "")
    private let chooseButton = NSButton(title: "Choose Music…", target: nil, action: nil)
    private let resetButton  = NSButton(title: "Use Default",   target: nil, action: nil)
    private let previewBtn   = NSButton(title: "▶ Preview 10s",  target: nil, action: nil)

    private let trimSlider   = NSSlider(value: 0, minValue: 0, maxValue: 1,
                                        target: nil, action: nil)
    private let trimLabel    = NSTextField(labelWithString: "")

    private let loginCheck   = NSButton(checkboxWithTitle: "Open at login",
                                        target: nil, action: nil)
    private let dramaCheck   = NSButton(checkboxWithTitle: "Play startup drama",
                                        target: nil, action: nil)

    private let versionLabel = NSTextField(labelWithString: "")
    private let updateLabel  = NSTextField(labelWithString: "Checking for updates…")
    private let updateButton = NSButton(title: "Check for updates",
                                        target: nil, action: nil)

    // MARK: – State

    private var soundDuration: TimeInterval = 0
    private var pendingDownloadURL: URL?
    private var pendingPageURL: URL?

    private var previewPlayer: AVAudioPlayer?
    private var previewStopper: Timer?

    private var keyMonitor: Any?

    // MARK: – Init

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        win.title = "Dramatic Events"
        win.center()
        win.isReleasedWhenClosed = false
        super.init(window: win)
        win.delegate = self
        buildUI()
        wireActions()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        refreshSoundUI()
        refreshLoginUI()
        refreshVersionUI()
        startUpdateCheck()
    }

    func windowWillClose(_ notification: Notification) {
        stopPreview()
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    /// Local key monitor so ⌘W closes the window and ⌘Q prompts before quitting,
    /// even though we're an `LSUIElement` accessory app without a top-level menu bar.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let win = self.window,
                  event.window === win,
                  event.modifierFlags.contains(.command)
            else { return event }

            switch event.charactersIgnoringModifiers {
            case "w":
                win.performClose(nil)
                return nil
            case "q":
                self.confirmQuit()
                return nil
            default:
                return event
            }
        }
    }

    private func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = "Quit Dramatic Events?"
        alert.informativeText = "You won't get countdowns or sound alerts until you reopen it."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    // MARK: – UI construction

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor)
        ])

        // — Sound section —
        stack.addArrangedSubview(sectionHeader("Sound"))
        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.maximumNumberOfLines = 1
        let fileRow = NSStackView(views: [fileLabel])
        fileRow.alignment = .centerY
        stack.addArrangedSubview(fileRow)

        let buttonRow = NSStackView(views: [chooseButton, resetButton, previewBtn])
        buttonRow.spacing = 8
        stack.addArrangedSubview(buttonRow)

        trimSlider.controlSize = .small
        trimSlider.target = self
        trimSlider.action = #selector(trimChanged)
        let sliderWidth = trimSlider.widthAnchor.constraint(equalToConstant: 432)
        sliderWidth.priority = .defaultHigh
        sliderWidth.isActive = true
        stack.addArrangedSubview(trimSlider)

        trimLabel.font = NSFont.systemFont(ofSize: 11)
        trimLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(trimLabel)

        stack.addArrangedSubview(divider())

        // — Startup —
        stack.addArrangedSubview(sectionHeader("Startup"))
        loginCheck.target = self
        loginCheck.action = #selector(loginToggled)
        stack.addArrangedSubview(loginCheck)

        dramaCheck.target = self
        dramaCheck.action = #selector(dramaToggled)
        dramaCheck.toolTip = "Play a 20-second \"Going live\" intro every time the app launches."
        stack.addArrangedSubview(dramaCheck)

        stack.addArrangedSubview(divider())

        // — About —
        stack.addArrangedSubview(sectionHeader("About"))
        versionLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        stack.addArrangedSubview(versionLabel)

        updateLabel.font = NSFont.systemFont(ofSize: 11)
        updateLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(updateLabel)

        stack.addArrangedSubview(updateButton)

        // — Footer —
        let footerSpacer = NSView()
        footerSpacer.heightAnchor.constraint(equalToConstant: 4).isActive = true
        stack.addArrangedSubview(footerSpacer)
        stack.addArrangedSubview(makeFooterLink())
    }

    /// "Made by Omar Osama" — only the name is underlined and clickable.
    private func makeFooterLink() -> NSTextField {
        let plain = NSAttributedString(
            string: "Made by ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ])
        let link = NSMutableAttributedString(
            string: "Omar Osama",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .link: URL(string: "https://www.linkedin.com/in/ulvosama/")!,
                .cursor: NSCursor.pointingHand
            ])
        let composed = NSMutableAttributedString()
        composed.append(plain)
        composed.append(link)

        let field = NSTextField(labelWithAttributedString: composed)
        field.isSelectable = true
        field.allowsEditingTextAttributes = true
        return field
    }

    private func sectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func divider() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 432).isActive = true
        return line
    }

    // MARK: – Wiring

    private func wireActions() {
        chooseButton.target = self;  chooseButton.action = #selector(chooseMusic)
        resetButton.target  = self;  resetButton.action  = #selector(resetMusic)
        previewBtn.target   = self;  previewBtn.action   = #selector(togglePreview)
        updateButton.target = self;  updateButton.action = #selector(updateButtonTapped)
    }

    @objc private func dramaToggled() {
        Settings.shared.startupDramaEnabled = (dramaCheck.state == .on)
    }

    // MARK: – Sound UI

    private func refreshSoundUI() {
        fileLabel.stringValue = "Current: \(Settings.shared.soundDisplayName)"
        resetButton.isEnabled = Settings.shared.usesCustomSound

        guard let url = Settings.shared.effectiveSoundURL,
              let probe = try? AVAudioPlayer(contentsOf: url) else {
            soundDuration = 0
            trimSlider.isEnabled = false
            trimLabel.stringValue = "Audio unavailable"
            return
        }
        soundDuration = probe.duration

        if soundDuration <= 10 {
            trimSlider.isEnabled = false
            trimSlider.maxValue = 0
            trimSlider.doubleValue = 0
            Settings.shared.trimStart = 0
            trimLabel.stringValue = String(
                format: "Plays the whole file (%@). Trim disabled — clip is shorter than 10 s.",
                formatTime(soundDuration))
        } else {
            trimSlider.isEnabled = true
            trimSlider.minValue = 0
            trimSlider.maxValue = soundDuration - 10
            let clamped = max(0, min(Settings.shared.trimStart, trimSlider.maxValue))
            trimSlider.doubleValue = clamped
            Settings.shared.trimStart = clamped
            updateTrimLabel()
        }
    }

    private func updateTrimLabel() {
        let start = trimSlider.doubleValue
        trimLabel.stringValue = "Plays from \(formatTime(start)) to \(formatTime(start + 10))"
    }

    private func formatTime(_ s: TimeInterval) -> String {
        let total = Int(s.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @objc private func trimChanged() {
        Settings.shared.trimStart = trimSlider.doubleValue
        updateTrimLabel()
    }

    @objc private func chooseMusic() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.mp3, .wav, .mpeg4Audio, .aiff, .audio]
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                _ = try Settings.shared.setCustomSound(from: url)
            } catch {
                self.alert("Couldn't import audio file: \(error.localizedDescription)")
                return
            }
            self.refreshSoundUI()
        }
    }

    @objc private func resetMusic() {
        Settings.shared.resetSound()
        refreshSoundUI()
    }

    @objc private func togglePreview() {
        if previewPlayer?.isPlaying == true {
            stopPreview()
            return
        }
        guard let url = Settings.shared.effectiveSoundURL,
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        let start = min(Settings.shared.trimStart, max(0, p.duration - 0.1))
        let length = min(10.0, p.duration - start)
        p.currentTime = start
        p.volume = 0
        p.play()
        p.setVolume(1.0, fadeDuration: 2.0)
        previewPlayer = p
        previewBtn.title = "■ Stop preview"

        previewStopper?.invalidate()
        previewStopper = Timer.scheduledTimer(withTimeInterval: length, repeats: false) {
            [weak self] _ in self?.stopPreview()
        }
    }

    private func stopPreview() {
        previewStopper?.invalidate()
        previewStopper = nil
        previewPlayer?.stop()
        previewPlayer = nil
        previewBtn.title = "▶ Preview 10s"
    }

    // MARK: – Login UI

    private func refreshLoginUI() {
        loginCheck.state = LoginItemHelper.isEnabled ? .on : .off
        dramaCheck.state = Settings.shared.startupDramaEnabled ? .on : .off
    }

    @objc private func loginToggled() {
        let want = (loginCheck.state == .on)
        if !LoginItemHelper.setEnabled(want) {
            // Roll back the checkbox state if the system rejected it.
            loginCheck.state = LoginItemHelper.isEnabled ? .on : .off
            if let err = LoginItemHelper.lastError {
                alert("Couldn't update login items: \(err.localizedDescription)")
            }
        }
    }

    // MARK: – Version / Updates UI

    private func refreshVersionUI() {
        versionLabel.stringValue = "Dramatic Events v\(UpdateChecker.currentVersion)"
    }

    private func startUpdateCheck() {
        updateLabel.stringValue = "Checking for updates…"
        updateLabel.textColor = .secondaryLabelColor
        updateButton.isEnabled = false
        updateButton.title = "Check for updates"
        pendingDownloadURL = nil
        pendingPageURL = nil

        UpdateChecker.check { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateButton.isEnabled = true
                switch result {
                case .upToDate(let v):
                    self.updateLabel.stringValue = "You're on the latest version (v\(v))."
                    self.updateLabel.textColor = .secondaryLabelColor
                    self.updateButton.title = "Check for updates"
                case .updateAvailable(let r):
                    self.updateLabel.stringValue = "Update available — v\(r.version)"
                    self.updateLabel.textColor = .systemOrange
                    self.updateButton.title = "Download v\(r.version)"
                    self.pendingDownloadURL = r.downloadURL
                    self.pendingPageURL = r.pageURL
                case .failed(let err):
                    self.updateLabel.stringValue = "Couldn't reach update server: \(err.localizedDescription)"
                    self.updateLabel.textColor = .systemRed
                    self.updateButton.title = "Try again"
                }
            }
        }
    }

    @objc private func updateButtonTapped() {
        if let url = pendingDownloadURL ?? pendingPageURL {
            NSWorkspace.shared.open(url)
        } else {
            startUpdateCheck()
        }
    }

    // MARK: – Helpers

    private func alert(_ message: String) {
        let a = NSAlert()
        a.messageText = "Dramatic Events"
        a.informativeText = message
        a.alertStyle = .warning
        a.addButton(withTitle: "OK")
        if let w = window { a.beginSheetModal(for: w, completionHandler: nil) }
        else { a.runModal() }
    }
}
