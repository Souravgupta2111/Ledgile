import UIKit

final class ShopAssistantViewController: UIViewController, UITableViewDataSource, UITextViewDelegate {

    private struct Line {
        var isUser: Bool
        var text: String
    }

    private var lines: [Line] = [
        Line(isUser: false, text: "Ask anything about this shop — today’s sales, stock, udhaar, a customer, or a product. I read the ledger on this phone.")
    ]

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let inputBar = UIView()
    private let composer = UITextView()
    private let placeholderLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private let liveButton = UIButton(type: .system)
    private var isSending = false
    private var assistant: AnyObject?

    // MARK: - Assistant Live (full-screen voice modal; history lands here on close)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Assistant"
        view.backgroundColor = .systemGray6
        navigationItem.largeTitleDisplayMode = .never

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemGray6
        tableView.keyboardDismissMode = .interactive
        tableView.register(BubbleCell.self, forCellReuseIdentifier: "bubble")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72

        inputBar.translatesAutoresizingMaskIntoConstraints = false
        inputBar.backgroundColor = .secondarySystemBackground

        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.font = .preferredFont(forTextStyle: .body)
        composer.textColor = .label
        composer.backgroundColor = .tertiarySystemFill
        composer.layer.cornerRadius = 18
        composer.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        composer.delegate = self
        composer.isScrollEnabled = false

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = "Ask about sales, stock, or udhaar…"
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.textColor = .tertiaryLabel
        placeholderLabel.numberOfLines = 1
        placeholderLabel.isUserInteractionEnabled = false

        var sendConfig = UIButton.Configuration.filled()
        sendConfig.image = UIImage(systemName: "arrow.up")
        sendConfig.cornerStyle = .capsule
        sendConfig.baseBackgroundColor = UIColor(named: "Lime Moss") ?? .systemGreen
        sendConfig.baseForegroundColor = .white
        sendButton.configuration = sendConfig
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        var liveConfig = UIButton.Configuration.filled()
        liveConfig.image = UIImage(systemName: "mic.fill")
        liveConfig.cornerStyle = .capsule
        liveConfig.baseBackgroundColor = UIColor(named: "Lime Moss") ?? .systemGreen
        liveConfig.baseForegroundColor = .white
        liveButton.configuration = liveConfig
        liveButton.translatesAutoresizingMaskIntoConstraints = false
        liveButton.addTarget(self, action: #selector(liveTapped), for: .touchUpInside)

        view.addSubview(tableView)
        view.addSubview(inputBar)
        inputBar.addSubview(composer)
        composer.addSubview(placeholderLabel)
        inputBar.addSubview(liveButton)
        inputBar.addSubview(sendButton)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),

            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            composer.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 12),
            composer.topAnchor.constraint(equalTo: inputBar.topAnchor, constant: 8),
            composer.bottomAnchor.constraint(equalTo: inputBar.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            composer.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            composer.heightAnchor.constraint(lessThanOrEqualToConstant: 120),

            placeholderLabel.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 14),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: composer.trailingAnchor, constant: -12),
            placeholderLabel.centerYAnchor.constraint(equalTo: composer.centerYAnchor),

            liveButton.leadingAnchor.constraint(equalTo: composer.trailingAnchor, constant: 8),
            liveButton.bottomAnchor.constraint(equalTo: composer.bottomAnchor),
            liveButton.widthAnchor.constraint(equalToConstant: 36),
            liveButton.heightAnchor.constraint(equalToConstant: 36),

            sendButton.leadingAnchor.constraint(equalTo: liveButton.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -12),
            sendButton.bottomAnchor.constraint(equalTo: composer.bottomAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        if #available(iOS 26.0, *) {
            if ShopAssistantService.isAvailable {
                assistant = ShopAssistantService()
            } else {
                lines.append(Line(isUser: false, text: ShopAssistantService.unavailableMessage))
            }
        } else {
            lines.append(Line(isUser: false, text: "Assistant needs iOS 26 or later."))
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        lines.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "bubble", for: indexPath) as! BubbleCell
        cell.configure(text: lines[indexPath.row].text, isUser: lines[indexPath.row].isUser)
        return cell
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            sendTapped()
            return false
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc private func sendTapped() {
        let text = composer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        composer.text = ""
        placeholderLabel.isHidden = false
        lines.append(Line(isUser: true, text: text))
        lines.append(Line(isUser: false, text: "Fetching..."))
        tableView.reloadData()
        scrollToEnd()
        isSending = true
        sendButton.isEnabled = false

        Task { @MainActor in
            defer {
                isSending = false
                sendButton.isEnabled = true
            }
            do {
                let answer = try await ask(text)
                lines[lines.count - 1].text = answer.isEmpty ? "I could not form an answer from the ledger." : answer
            } catch {
                lines[lines.count - 1].text = error.localizedDescription
            }
            tableView.reloadData()
            scrollToEnd()
        }
    }

    private func ask(_ text: String) async throws -> String {
        if #available(iOS 26.0, *) {
            guard let service = assistant as? ShopAssistantService else {
                return ShopAssistantService.unavailableMessage
            }
            return try await service.streamReply(to: text) { [weak self] partial in
                guard let self else { return }
                guard !self.lines.isEmpty else { return }
                self.lines[self.lines.count - 1].text = partial
                self.tableView.reloadData()
                self.scrollToEnd()
            }
        }
        return "Assistant needs iOS 26 or later."
    }

    private func scrollToEnd() {
        let row = lines.count - 1
        guard row >= 0 else { return }
        tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .bottom, animated: false)
    }

    // MARK: - Live voice (full-screen modal; turns land here as bubbles on close)

    @objc private func liveTapped() {
        let snap = ShopLedgerLookup.shopSnapshot()
        let top = ShopLedgerLookup.topSellingProducts(limit: 5)
        let low = ShopLedgerLookup.lowStock()
        let pack = [snap, top, "LOWSTOCK:\n" + low].joined(separator: "\n")
        let vc = LiveVoiceViewController(shopPack: pack)
        vc.onExit = { [weak self] turns in
            guard let self, !turns.isEmpty else { return }
            for t in turns {
                self.lines.append(Line(isUser: true, text: t.user))
                self.lines.append(Line(isUser: false, text: t.assistant))
            }
            self.tableView.reloadData()
            self.scrollToEnd()
        }
        present(vc, animated: true)
    }
}

private final class BubbleCell: UITableViewCell {
    private let bubble = UIView()
    private let label = UILabel()
    private var userTrailing: NSLayoutConstraint!
    private var assistantLeading: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        bubble.layer.cornerRadius = 16
        bubble.clipsToBounds = true
        bubble.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.font = .preferredFont(forTextStyle: .body)
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubble)
        bubble.addSubview(label)
        userTrailing = bubble.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        assistantLeading = bubble.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            bubble.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            bubble.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 16),
            bubble.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.82),
            assistantLeading,
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    func configure(text: String, isUser: Bool) {
        label.text = text
        label.textColor = isUser ? .white : .label
        bubble.backgroundColor = isUser
            ? (UIColor(named: "Lime Moss") ?? .systemGreen)
            : .secondarySystemBackground
        userTrailing.isActive = isUser
        assistantLeading.isActive = !isUser
    }
}
