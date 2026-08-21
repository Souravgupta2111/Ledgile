import UIKit

class UPICollectionSettingsViewController: UITableViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    private enum Section: Int, CaseIterable {
        case details
        case preview
    }

    private enum DetailRow: Int, CaseIterable {
        case vpa
        case qr
    }

    private var appSettings: AppSettings
    private let vpaField = UITextField()
    private let lime = UIColor(named: "Lime Moss") ?? .systemGreen

    init() {
        self.appSettings = (try? AppDataModel.shared.dataModel.db.getSettings()) ?? AppSettings(
            invoicePrefix: "INV", invoiceNumberCounter: 1, includeYearInInvoice: false,
            businessName: "My Shop", expiryNoticeDays: 14, expiryWarningDays: 7, expiryCriticalDays: 3
        )
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "UPI Collection"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = .systemGroupedBackground
        navigationController?.navigationBar.tintColor = lime
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(saveTapped))
        navigationItem.rightBarButtonItem?.tintColor = lime

        vpaField.placeholder = "shopname@paytm"
        vpaField.autocapitalizationType = .none
        vpaField.autocorrectionType = .no
        vpaField.keyboardType = .emailAddress
        vpaField.text = appSettings.upiVPA
        vpaField.textAlignment = .right
        vpaField.clearButtonMode = .whileEditing
        vpaField.font = .preferredFont(forTextStyle: .body)
        vpaField.textColor = .secondaryLabel
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        appSettings.upiQRImageData == nil ? 1 : Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .details: return DetailRow.allCases.count
        case .preview: return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .details: return "PhonePe / Paytm / GPay"
        case .preview: return "QR Preview"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard Section(rawValue: section) == .details else { return nil }
        return "UPI ID fills the amount automatically. WhatsApp sends a pay link plus a QR for that rupee amount. The customer still enters UPI PIN. When money arrives, tap You Received — this app does not watch your wallet."
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        Section(rawValue: indexPath.section) == .preview ? 220 : 50
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "cell")
        cell.selectionStyle = .none
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.backgroundColor = .secondarySystemGroupedBackground

        guard let section = Section(rawValue: indexPath.section) else { return cell }

        switch section {
        case .details:
            switch DetailRow(rawValue: indexPath.row) {
            case .vpa:
                cell.textLabel?.text = "UPI ID"
                vpaField.frame = CGRect(x: 0, y: 0, width: 200, height: 32)
                cell.accessoryView = vpaField
            case .qr:
                cell.selectionStyle = .default
                cell.textLabel?.text = "QR Screenshot"
                cell.detailTextLabel?.text = appSettings.upiQRImageData == nil ? "Add" : "Change"
                cell.accessoryType = .disclosureIndicator
            case .none:
                break
            }
        case .preview:
            cell.selectionStyle = .none
            cell.textLabel?.text = nil
            cell.detailTextLabel?.text = nil
            let tag = 88
            cell.contentView.viewWithTag(tag)?.removeFromSuperview()
            if let data = appSettings.upiQRImageData, let image = UIImage(data: data) {
                let imageView = UIImageView(image: image)
                imageView.tag = tag
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.contentMode = .scaleAspectFit
                imageView.layer.cornerRadius = 12
                imageView.clipsToBounds = true
                imageView.backgroundColor = .white
                cell.contentView.addSubview(imageView)
                NSLayoutConstraint.activate([
                    imageView.centerXAnchor.constraint(equalTo: cell.contentView.centerXAnchor),
                    imageView.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 168),
                    imageView.heightAnchor.constraint(equalToConstant: 168)
                ])
            }
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Section(rawValue: indexPath.section) == .details,
              DetailRow(rawValue: indexPath.row) == .qr else { return }
        pickQRImage()
    }

    private func pickQRImage() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.allowsEditing = true
        let sheet = UIAlertController(title: "UPI QR", message: "Screenshot your QR from PhonePe, Paytm, or GPay.", preferredStyle: .actionSheet)
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            sheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { _ in
                picker.sourceType = .photoLibrary
                self.present(picker, animated: true)
            })
        }
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            sheet.addAction(UIAlertAction(title: "Camera", style: .default) { _ in
                picker.sourceType = .camera
                self.present(picker, animated: true)
            })
        }
        if appSettings.upiQRImageData != nil {
            sheet.addAction(UIAlertAction(title: "Remove QR", style: .destructive) { _ in
                self.appSettings.upiQRImageData = nil
                self.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        appSettings.upiQRImageData = image?.jpegData(compressionQuality: 0.8)
        picker.dismiss(animated: true) {
            self.tableView.reloadData()
        }
    }

    @objc private func saveTapped() {
        appSettings.upiVPA = vpaField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if appSettings.upiVPA?.isEmpty == true {
            appSettings.upiVPA = nil
        }
        try? AppDataModel.shared.dataModel.db.updateSettings(appSettings)
        navigationController?.popViewController(animated: true)
    }
}
