import UIKit

/// Capsule label with built-in horizontal and vertical padding to prevent text clipping.
private final class PaddedPillLabel: UILabel {
    var insets = UIEdgeInsets(top: 4, left: 14, bottom: 4, right: 14)
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + insets.left + insets.right,
                      height: max(28, s.height + insets.top + insets.bottom))
    }
}

/// Full-screen voice conversation (ChatGPT-voice style, app theme).
/// Center orb + ONE status word only — no transcript here.
/// Voice turns land in the normal chat as bubbles when this closes.
/// Loop: Whisper-small Roman (30s max, 1.2s cut) -> Qwen 3.7 -> read-only
/// SQL on the full ledger -> Bulbul Anushka streaming. Auto-loop, barge-in.
final class LiveVoiceViewController: UIViewController {

    /// Flushed on close: every finished (user, assistant) turn for chat bubbles.
    var onExit: (([(user: String, assistant: String)]) -> Void)?

    private let shopPack: String
    private var history: [(user: String, assistant: String)] = []

    private let orb = LiveOrbView()
    private let statusLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let livePill = PaddedPillLabel()
    private let bottomBar = UIView()
    private let askField = UITextField()
    private let muteButton = UIButton(type: .system)
    private let endButton = UIButton(type: .system)

    private var engine: LiveAssistantEngine?
    private var reasoner: QwenLiveReasoner?
    private var speaker: SarvamBulbulSpeaker?
    private var isMuted = false
    private var isClosing = false

    init(shopPack: String) {
        self.shopPack = shopPack
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    // MARK: - view

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark ? .black : .systemGray6
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        setupKeyboardObservers()

        // Top-left close.
        var closeCfg = UIButton.Configuration.plain()
        closeCfg.image = UIImage(systemName: "xmark")
        closeButton.configuration = closeCfg
        closeButton.tintColor = .label
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        // Top-right Live pill.
        livePill.translatesAutoresizingMaskIntoConstraints = false
        livePill.text = "●  Live"
        livePill.font = .preferredFont(forTextStyle: .subheadline)
        livePill.textColor = .white
        livePill.textAlignment = .center
        livePill.backgroundColor = UIColor(named: "Lime Moss") ?? .systemGreen
        livePill.layer.cornerRadius = 14
        livePill.clipsToBounds = true

        orb.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "Listening..."
        statusLabel.font = .preferredFont(forTextStyle: .title3)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.minimumScaleFactor = 0.75
        statusLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        // Bottom bar: [Ask field] [mic] [X].
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.backgroundColor = .secondarySystemBackground
        bottomBar.layer.cornerRadius = 26

        askField.translatesAutoresizingMaskIntoConstraints = false
        askField.placeholder = "Ask..."
        askField.font = .preferredFont(forTextStyle: .body)
        askField.returnKeyType = .send
        askField.adjustsFontSizeToFitWidth = true
        askField.minimumFontSize = 13
        askField.clearButtonMode = .whileEditing
        askField.delegate = self

        var muteCfg = UIButton.Configuration.plain()
        muteCfg.image = UIImage(systemName: "mic.fill")
        muteButton.configuration = muteCfg
        muteButton.tintColor = .label
        muteButton.translatesAutoresizingMaskIntoConstraints = false
        muteButton.addTarget(self, action: #selector(muteTapped), for: .touchUpInside)

        var endCfg = UIButton.Configuration.filled()
        endCfg.image = UIImage(systemName: "xmark")
        endCfg.cornerStyle = .capsule
        endCfg.baseBackgroundColor = .systemRed
        endCfg.baseForegroundColor = .white
        endButton.configuration = endCfg
        endButton.translatesAutoresizingMaskIntoConstraints = false
        endButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        view.addSubview(closeButton)
        view.addSubview(livePill)
        view.addSubview(orb)
        view.addSubview(statusLabel)
        view.addSubview(bottomBar)
        bottomBar.addSubview(askField)
        view.addSubview(muteButton)
        view.addSubview(endButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            livePill.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            livePill.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            livePill.leadingAnchor.constraint(greaterThanOrEqualTo: closeButton.trailingAnchor, constant: 12),
            livePill.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),

            orb.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            orb.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            orb.widthAnchor.constraint(equalToConstant: 220),
            orb.heightAnchor.constraint(equalToConstant: 220),

            statusLabel.topAnchor.constraint(equalTo: orb.bottomAnchor, constant: 24),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomBar.topAnchor, constant: -12),

            bottomBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            bottomBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
            bottomBar.topAnchor.constraint(greaterThanOrEqualTo: statusLabel.bottomAnchor, constant: 8),
            bottomBar.heightAnchor.constraint(equalToConstant: 52),

            askField.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 18),
            askField.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            askField.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor),
            askField.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -12),

            muteButton.leadingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: 10),
            muteButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            muteButton.widthAnchor.constraint(equalToConstant: 48),
            muteButton.heightAnchor.constraint(equalToConstant: 48),

            endButton.leadingAnchor.constraint(equalTo: muteButton.trailingAnchor, constant: 6),
            endButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            endButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            endButton.widthAnchor.constraint(equalToConstant: 48),
            endButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        startLoop()
        HotwordListener.shared.pause()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        teardown()
        if !isClosing {
            isClosing = true
            onExit?(history)
        }
        HotwordListener.shared.resume()
    }

    // MARK: - loop

    private func startLoop() {
        reasoner = QwenLiveReasoner()
        reasoner?.reset()
        if engine == nil { engine = LiveAssistantEngine() }
        if speaker == nil {
            speaker = SarvamBulbulSpeaker()
            speaker?.onLevel = { [weak self] lvl in
                guard let self else { return }
                self.orb.level = lvl
            }
            speaker?.onDone = { [weak self] in
                guard let self, !self.isClosing, !self.isMuted else { return }
                self.setStatus(mode: .listening, text: "Listening...")
                self.engine?.monitorForBargeIn(false)
                self.engine?.listenAgain()
            }
            speaker?.onError = { [weak self] msg in
                guard let self, !self.isClosing else { return }
                LiveLog.ui("TTS error surfaced: \(msg)")
                self.setStatus(mode: .listening, text: "Voice unavailable — listening...")
                // Auto-clear after 2s so it doesn't stick.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, !self.isClosing, self.statusLabel.text == "Voice unavailable — listening..." else { return }
                    self.setStatus(mode: .listening, text: "Listening...")
                }
            }
        }
        engine?.onLevel = { [weak self] lvl in
            guard let self, !self.isClosing, self.orb.mode == .listening else { return }
            self.orb.level = lvl
        }
        engine?.onStatus = { [weak self] _, text in
            guard let self, !self.isClosing else { return }
            self.setStatus(mode: .listening, text: text)
        }
        engine?.onMicHint = { [weak self] hint in
            guard let self, !self.isClosing else { return }
            LiveLog.ui("mic hint (console only): \(hint)")
        }
        engine?.onFinal = { [weak self] roman in
            guard let self, !self.isClosing else { return }
            LiveLog.ui("turn heard: '\(roman.prefix(120))'")
            self.handleTurn(roman)
        }
        engine?.onBargeIn = { [weak self] in
            guard let self, !self.isClosing else { return }
            self.speaker?.stop()
            self.engine?.monitorForBargeIn(false)
            self.setStatus(mode: .listening, text: "Listening...")
            self.engine?.listenAgain()
        }
        setStatus(mode: .listening, text: "Listening...")
        engine?.start()
    }

    private func setStatus(mode: LiveOrbView.Mode, text: String) {
        orb.mode = mode
        statusLabel.text = text
    }

    private func handleTurn(_ roman: String) {
        setStatus(mode: .thinking, text: "Thinking...")
        LiveLog.ui("handleTurn start — asking Qwen")
        Task { @MainActor in
            do {
                guard let reasoner = self.reasoner, !self.isClosing else { return }
                let (answer, sql) = try await reasoner.ask(userText: roman, shopPack: self.shopPack)
                LiveLog.ui("Qwen answered (\(answer.count) chars)" + (sql != nil ? " + wants SQL" : ""))
                var final = answer
                if let sql, !sql.isEmpty {
                    LiveLog.ui("running shop SQL: \(sql.prefix(160))")
                    let result = Self.runShopSQL(sql)
                    LiveLog.ui("SQL result (\(result.count) chars) — asking Qwen for final")
                    final = try await reasoner.answerWithSQLResult(result, shopPack: self.shopPack)
                }
                let clean = LiveRomanFilter.toRoman(final)
                let show = clean.isEmpty ? "No data found." : clean
                guard !self.isClosing else { return }
                self.history.append((user: roman, assistant: show))
                self.updatePill()
                LiveLog.ui("turn #\(self.history.count) done — speaking (\(show.count) chars)")
                self.setStatus(mode: .speaking, text: "Speaking...")
                self.engine?.monitorForBargeIn(true)
                self.speaker?.speak(show)
            } catch {
                let msg = (error as NSError).localizedDescription
                LiveLog.ui("turn FAILED: \(msg)")
                guard !self.isClosing else { return }
                self.history.append((user: roman, assistant: msg))
                self.setStatus(mode: .listening, text: "Listening...")
                self.engine?.listenAgain()
            }
        }
    }

    private func updatePill() {
        livePill.text = history.isEmpty ? "●  Live" : "●  Live · \(history.count)"
    }

    static func runShopSQL(_ sql: String) -> String {
        do {
            let db = AppDataModel.shared.dataModel.db
            if let sdb = db as? SQLiteDatabase {
                let (cols, rows) = try sdb.runReadOnlySelect(sql, maxRows: 50)
                return SQLiteDatabase.formatReadOnlyResult(columns: cols, rows: rows)
            }
            return "SQL engine unavailable"
        } catch {
            return "SQL error: \(error.localizedDescription)"
        }
    }

    private func teardown() {
        engine?.stop()
        speaker?.stop()
    }

    // MARK: - actions

    @objc private func closeTapped() {
        isClosing = true
        teardown()
        onExit?(history)
        dismiss(animated: true)
    }

    @objc private func muteTapped() {
        isMuted.toggle()
        var cfg = muteButton.configuration
        cfg?.image = UIImage(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
        muteButton.configuration = cfg
        if isMuted {
            speaker?.stop()
            engine?.monitorForBargeIn(false)
            engine?.stop()
            setStatus(mode: .idle, text: "Muted")
        } else {
            setStatus(mode: .listening, text: "Listening...")
            engine?.listenAgain()
        }
    }

    // MARK: - Keyboard Handling

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curveValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else { return }

        let keyboardInView = view.convert(endFrame, from: nil)
        let isShowing = keyboardInView.origin.y < view.bounds.height

        let options = UIView.AnimationOptions(rawValue: curveValue << 16)
        UIView.animate(withDuration: duration, delay: 0, options: [options, .beginFromCurrentState]) {
            if isShowing {
                self.orb.transform = CGAffineTransform(scaleX: 0.65, y: 0.65).translatedBy(x: 0, y: -45)
                self.statusLabel.transform = CGAffineTransform(translationX: 0, y: -45)
            } else {
                self.orb.transform = .identity
                self.statusLabel.transform = .identity
            }
        }
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
}

extension LiveVoiceViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let t = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !t.isEmpty else { return false }
        textField.text = ""
        textField.resignFirstResponder()
        speaker?.stop()
        handleTurn(LiveRomanFilter.toRoman(t))
        return true
    }
}
