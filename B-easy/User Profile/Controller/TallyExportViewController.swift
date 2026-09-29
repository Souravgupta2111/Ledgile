import UIKit
import UniformTypeIdentifiers

/// Tally one-tap: export pending bills (app -> Tally XML file share)
/// + backward import (Tally DayBook XML -> mirror tables).
/// Same design tokens: systemGroupedBackground + Lime Moss capsule.
final class TallyExportViewController: UIViewController, UIDocumentPickerDelegate {

    private let scroll = UIScrollView()
    private let stack = UIStackView()

    private let pendingCard = UIView()
    private let pendingTitle = UILabel()
    private let pendingDetail = UILabel()
    private let exportButton = UIButton(type: .system)
    private let lastExportLabel = UILabel()

    private let importCard = UIView()
    private let importDetail = UILabel()
    private let importButton = UIButton(type: .system)

    private var dataModel: DataModel { AppDataModel.shared.dataModel }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tally Export"
        view.backgroundColor = .systemGroupedBackground

        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16

        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -32)
        ])

        buildPendingCard()
        buildImportCard()
        stack.addArrangedSubview(pendingCard)
        stack.addArrangedSubview(importCard)
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    // MARK: - cards

    private func cardStyle(_ v: UIView) {
        v.backgroundColor = .systemBackground
        v.layer.cornerRadius = 20
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.06
        v.layer.shadowRadius = 8
        v.layer.shadowOffset = CGSize(width: 0, height: 2)
    }

    private func buildPendingCard() {
        cardStyle(pendingCard)
        pendingTitle.translatesAutoresizingMaskIntoConstraints = false
        pendingDetail.translatesAutoresizingMaskIntoConstraints = false
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        lastExportLabel.translatesAutoresizingMaskIntoConstraints = false

        pendingTitle.font = .preferredFont(forTextStyle: .headline)
        pendingTitle.text = "Export to Tally"
        pendingDetail.font = .preferredFont(forTextStyle: .body)
        pendingDetail.numberOfLines = 0
        pendingDetail.textColor = .secondaryLabel
        lastExportLabel.font = .preferredFont(forTextStyle: .footnote)
        lastExportLabel.numberOfLines = 0
        lastExportLabel.textColor = .tertiaryLabel

        var cfg = UIButton.Configuration.filled()
        cfg.title = "Export Tally XML"
        cfg.image = UIImage(systemName: "square.and.arrow.up.fill")
        cfg.cornerStyle = .capsule
        cfg.baseBackgroundColor = UIColor(named: "Lime Moss") ?? .systemGreen
        cfg.baseForegroundColor = .white
        exportButton.configuration = cfg
        exportButton.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)

        pendingCard.addSubview(pendingTitle)
        pendingCard.addSubview(pendingDetail)
        pendingCard.addSubview(exportButton)
        pendingCard.addSubview(lastExportLabel)
        NSLayoutConstraint.activate([
            pendingTitle.topAnchor.constraint(equalTo: pendingCard.topAnchor, constant: 16),
            pendingTitle.leadingAnchor.constraint(equalTo: pendingCard.leadingAnchor, constant: 16),
            pendingTitle.trailingAnchor.constraint(equalTo: pendingCard.trailingAnchor, constant: -16),
            pendingDetail.topAnchor.constraint(equalTo: pendingTitle.bottomAnchor, constant: 8),
            pendingDetail.leadingAnchor.constraint(equalTo: pendingCard.leadingAnchor, constant: 16),
            pendingDetail.trailingAnchor.constraint(equalTo: pendingCard.trailingAnchor, constant: -16),
            exportButton.topAnchor.constraint(equalTo: pendingDetail.bottomAnchor, constant: 14),
            exportButton.leadingAnchor.constraint(equalTo: pendingCard.leadingAnchor, constant: 16),
            exportButton.trailingAnchor.constraint(equalTo: pendingCard.trailingAnchor, constant: -16),
            exportButton.heightAnchor.constraint(equalToConstant: 48),
            lastExportLabel.topAnchor.constraint(equalTo: exportButton.bottomAnchor, constant: 10),
            lastExportLabel.leadingAnchor.constraint(equalTo: pendingCard.leadingAnchor, constant: 16),
            lastExportLabel.trailingAnchor.constraint(equalTo: pendingCard.trailingAnchor, constant: -16),
            lastExportLabel.bottomAnchor.constraint(equalTo: pendingCard.bottomAnchor, constant: -16)
        ])
    }

    private func buildImportCard() {
        cardStyle(importCard)
        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .preferredFont(forTextStyle: .headline)
        title.text = "Import from Tally"
        importDetail.translatesAutoresizingMaskIntoConstraints = false
        importDetail.font = .preferredFont(forTextStyle: .body)
        importDetail.numberOfLines = 0
        importDetail.textColor = .secondaryLabel
        importButton.translatesAutoresizingMaskIntoConstraints = false

        var cfg = UIButton.Configuration.tinted()
        cfg.title = "Import Tally XML"
        cfg.image = UIImage(systemName: "tray.and.arrow.down.fill")
        cfg.cornerStyle = .capsule
        importButton.configuration = cfg
        importButton.addTarget(self, action: #selector(importTapped), for: .touchUpInside)

        importCard.addSubview(title)
        importCard.addSubview(importDetail)
        importCard.addSubview(importButton)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: importCard.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: importCard.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: importCard.trailingAnchor, constant: -16),
            importDetail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            importDetail.leadingAnchor.constraint(equalTo: importCard.leadingAnchor, constant: 16),
            importDetail.trailingAnchor.constraint(equalTo: importCard.trailingAnchor, constant: -16),
            importButton.topAnchor.constraint(equalTo: importDetail.bottomAnchor, constant: 14),
            importButton.leadingAnchor.constraint(equalTo: importCard.leadingAnchor, constant: 16),
            importButton.trailingAnchor.constraint(equalTo: importCard.trailingAnchor, constant: -16),
            importButton.heightAnchor.constraint(equalToConstant: 48),
            importButton.bottomAnchor.constraint(equalTo: importCard.bottomAnchor, constant: -16)
        ])
    }

    // MARK: - data

    private func refresh() {
        let counts = TallyExporter.pendingCounts(db: dataModel.db)
        if counts.total == 0 {
            pendingDetail.text = "All bills are exported."
        } else {
            var parts: [String] = []
            if counts.sales > 0 { parts.append("\(counts.sales) sales (₹\(Int(counts.saleAmount)))") }
            if counts.purchases > 0 { parts.append("\(counts.purchases) purchases (₹\(Int(counts.purchaseAmount)))") }
            pendingDetail.text = parts.joined(separator: " · ") + " ready to export."
                + "\n\nOpen your company in Tally, then import the file under Import Data → Vouchers."
        }
        if let sdb = dataModel.db as? SQLiteDatabase {
            let info = sdb.getTallyExportInfo()
            if info.count > 0 {
                lastExportLabel.text = "Synced \(info.count) vouchers." + (info.lastFile.map { " (\($0))" } ?? "")
            } else {
                lastExportLabel.text = "No exports yet."
            }
            let m = sdb.getTallyMirrorCounts()
            if m.vouchers == 0 {
                importDetail.text = "Import a Tally Day Book XML file. Your app ledger stays unchanged."
            } else {
                importDetail.text = "\(m.vouchers) vouchers · \(m.parties) parties imported." + (m.lastFile.map { "\nLast file: \($0)" } ?? "")
            }
        }
    }

    // MARK: - actions

    @objc private func exportTapped() {
        exportButton.isEnabled = false
        defer { exportButton.isEnabled = true }
        do {
            let result = try TallyExporter.exportPending(db: dataModel.db)
            refresh()
            let activity = UIActivityViewController(activityItems: [result.url], applicationActivities: nil)
            activity.completionWithItemsHandler = { [weak self] _, _, _, _ in self?.refresh() }
            if let pop = activity.popoverPresentationController {
                pop.sourceView = exportButton
                pop.sourceRect = exportButton.bounds
            }
            present(activity, animated: true)
        } catch {
            showInfo(title: "Tally Export", message: (error as NSError).localizedDescription)
        }
    }

    @objc private func importTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.xml, UTType.data], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            let (n, name) = try TallyImporter.importFile(url: url, db: dataModel.db)
            refresh()
            showInfo(title: "Import complete", message: "\(n) vouchers imported (\(name)). Your app ledger is unchanged.")
        } catch {
            showInfo(title: "Import failed", message: (error as NSError).localizedDescription)
        }
    }

    private func showInfo(title: String, message: String) {
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }
}
