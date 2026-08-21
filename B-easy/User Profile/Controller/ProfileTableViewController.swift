import UIKit
import QuickLook
import SafariServices

class ProfileTableViewController: UITableViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    private enum Section: Int, CaseIterable {
        case profile
        case general
        case reports
        case preferences
        case legal
        case settings
    }

    private enum GeneralRow: Int, CaseIterable {
        case beasyPro
        case upiCollection
        case gstSettings
    }

    private enum ReportsRow: Int, CaseIterable {
        case byItem
        case bySales
        case byCredit
        case gstr1
        case gstr3b
    }

    private var currentReportsRows: [ReportsRow] {
        var base: [ReportsRow] = [.byItem, .bySales, .byCredit]
        if let settings = appSettings, settings.isGSTRegistered, settings.gstScheme == "regular" {
            base.append(.gstr1)
            base.append(.gstr3b)
        }
        return base
    }

    private enum PreferencesRow: Int, CaseIterable {
        case appAppearance
        case dataBackup
        case cloudBackup
        case importBackup
        case restoreCloudBackup
        case mobileSAM
    }

    /// Visible preferences rows (mobileSAM only shows when model files exist on disk)
    private var currentPreferencesRows: [PreferencesRow] {
        var rows: [PreferencesRow] = [.appAppearance, .dataBackup, .cloudBackup, .importBackup, .restoreCloudBackup]
        if MobileSAMService.modelsExistOnDisk {
            rows.append(.mobileSAM)
        }
        return rows
    }

    private enum LegalRow: Int, CaseIterable {
        case termsAndConditions
        case privacyPolicy
        case aboutApp
    }

    private enum SettingsRow: Int, CaseIterable {
        case logOut
        case deleteAccount
    }

    private enum AppearanceMode: String {
        case system
        case light
        case dark
    }

    private enum NotificationPreset: String {
        case all
        case essentials
        case none
    }

    private enum DefaultsKey {
        static let appearanceMode = "profile.appearance.mode"
        static let notificationPreset = "profile.notifications.preset"
        static let pushEnabled = "profile.settings.push.enabled"
        static let businessEmail = "profile.businessEmail"
        static let businessWebsite = "profile.businessWebsite"
    }

    private var appSettings: AppSettings?
    private var pdfPreviewDataSource: PDFPreviewDataSource?
    private var dataModel: DataModel {
        AppDataModel.shared.dataModel
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTableView()
        loadData()
        applySavedAppearance()
        refreshEmailFromSupabase()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadData()
        tableView.reloadData()
    }

    private func configureTableView() {
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 60, bottom: 0, right: 0)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.contentInset.bottom = 24
        tableView.register(
            UINib(nibName: "ProfileContentsTopTableViewCell", bundle: nil),
            forCellReuseIdentifier: "ProfileContentsTopTableViewCell"
        )
        tableView.register(
            UINib(nibName: "ProfileContentsTableViewCell", bundle: nil),
            forCellReuseIdentifier: "ProfileContentsTableViewCell"
        )
        navigationItem.title = "Account"
    }

    private func loadData() {
        appSettings = try? dataModel.db.getSettings()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .profile: return 1
        case .general: return GeneralRow.allCases.count
        case .reports: return 0
        case .preferences: return currentPreferencesRows.count
        case .legal: return LegalRow.allCases.count
        case .settings: return SettingsRow.allCases.count
        }
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let section = Section(rawValue: indexPath.section) else { return 50 }
        return section == .profile ? UITableView.automaticDimension : 50
    }

    override func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let section = Section(rawValue: indexPath.section) else { return 50 }
        return section == .profile ? 186 : 50
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .profile: return nil
        case .general: return "General"
        case .reports: return nil
        case .preferences: return "Preferences"
        case .legal: return "Legal"
        case .settings: return "Settings"
        }
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard let sectionType = Section(rawValue: section) else { return 36 }
        return sectionType == .profile || sectionType == .reports ? 0.01 : 36
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch section {
        case .profile:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: "ProfileContentsTopTableViewCell",
                for: indexPath
            ) as? ProfileContentsTopTableViewCell else {
                return UITableViewCell()
            }

            cell.configure(
                ownerName: resolvedProfileName(),
                shopName: resolvedStoreName(),
                phone: resolvedPhoneNumber(),
                email: resolvedEmail(),
                address: resolvedAddress(),
                gstin: resolvedGSTIN(),
                website: resolvedWebsite()
            )
            cell.onShareTapped = { [weak self, weak cell] in
                guard let cell else { return }
                self?.shareBusinessCard(image: cell.cardImageForShare())
            }
            cell.onFieldTapped = { [weak self] field in
                self?.handleBusinessCardField(field)
            }
            return cell

        case .general:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: "ProfileContentsTableViewCell",
                for: indexPath
            ) as? ProfileContentsTableViewCell,
            let row = GeneralRow(rawValue: indexPath.row) else {
                return UITableViewCell()
            }

            switch row {
            case .beasyPro:
                cell.configure(
                    icon: UIImage(systemName: "sparkles"),
                    title: UsageTracker.shared.isProUser ? "B-easy Pro" : "B-easy Pro — ₹\(UsageTracker.monthlyPriceINR)/mo",
                    accessoryStyle: .chevron
                )
            case .upiCollection:
                let ready = UPIWhatsAppShare.canCollect(with: appSettings)
                cell.configure(
                    icon: UIImage(systemName: "qrcode"),
                    title: ready ? "UPI collection (WhatsApp)" : "UPI collection — add QR",
                    accessoryStyle: .chevron
                )
            case .gstSettings:
                let gstStatus = (appSettings?.isGSTRegistered ?? false) ? "Enabled" : "Disabled"
                cell.configure(
                    icon: UIImage(systemName: "percent"),
                    title: "GST Settings (\(gstStatus))",
                    accessoryStyle: .chevron
                )
            }
            return cell

        case .reports:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: "ProfileContentsTableViewCell",
                for: indexPath
            ) as? ProfileContentsTableViewCell else {
                return UITableViewCell()
            }
            let row = currentReportsRows[indexPath.row]

            switch row {
            case .byItem:
                cell.configure(
                    icon: UIImage(systemName: "cube.box.fill"),
                    title: "Report by Item",
                    accessoryStyle: .chevron
                )
            case .bySales:
                cell.configure(
                    icon: UIImage(systemName: "chart.line.uptrend.xyaxis"),
                    title: "Report by Sales",
                    accessoryStyle: .chevron
                )
            case .byCredit:
                cell.configure(
                    icon: UIImage(systemName: "creditcard.fill"),
                    title: "Report by Credit",
                    accessoryStyle: .chevron
                )
            case .gstr1:
                cell.configure(
                    icon: UIImage(systemName: "doc.badge.gearshape.fill"),
                    title: "GSTR-1 JSON Export",
                    accessoryStyle: .chevron
                )
            case .gstr3b:
                cell.configure(
                    icon: UIImage(systemName: "doc.badge.gearshape.fill"),
                    title: "GSTR-3B JSON Export",
                    accessoryStyle: .chevron
                )
            }
            return cell

        case .preferences:
            let prefRows = currentPreferencesRows
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: "ProfileContentsTableViewCell",
                for: indexPath
            ) as? ProfileContentsTableViewCell,
            indexPath.row < prefRows.count else {
                return UITableViewCell()
            }
            let row = prefRows[indexPath.row]

            switch row {
            case .appAppearance:
                cell.configure(
                    icon: UIImage(systemName: "paintbrush.fill"),
                    title: "App Appearance: \(currentAppearanceTitle())",
                    accessoryStyle: .chevron
                )

            case .dataBackup:
                cell.configure(
                    icon: UIImage(systemName: "tray.and.arrow.up.fill"),
                    title: "Save Local Backup",
                    accessoryStyle: .chevron
                )
            case .cloudBackup:
                cell.configure(
                    icon: UIImage(systemName: "icloud.and.arrow.up.fill"),
                    title: "Backup to Cloud",
                    accessoryStyle: .chevron
                )
            case .importBackup:
                cell.configure(
                    icon: UIImage(systemName: "tray.and.arrow.down.fill"),
                    title: "Import Backup",
                    accessoryStyle: .chevron
                )
            case .restoreCloudBackup:
                cell.configure(
                    icon: UIImage(systemName: "icloud.and.arrow.down.fill"),
                    title: "Restore Cloud Backup",
                    accessoryStyle: .chevron
                )
            case .mobileSAM:
                let isOn = UserDefaults.standard.bool(forKey: MobileSAMService.enabledKey)
                cell.configure(
                    icon: UIImage(systemName: "cpu"),
                    title: "MobileSAM Segmentation",
                    accessoryStyle: .toggle(isOn: isOn)
                )
                cell.onToggleChanged = { newValue in
                    UserDefaults.standard.set(newValue, forKey: MobileSAMService.enabledKey)
                    print("[Settings] MobileSAM toggled \(newValue ? "ON" : "OFF")")
                }
            }
            return cell

        case .legal:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: "ProfileContentsTableViewCell",
                for: indexPath
            ) as? ProfileContentsTableViewCell,
            let row = LegalRow(rawValue: indexPath.row) else {
                return UITableViewCell()
            }

            switch row {
            case .termsAndConditions:
                cell.configure(
                    icon: UIImage(systemName: "doc.text.fill"),
                    title: "Terms & Conditions",
                    accessoryStyle: .chevron
                )
            case .privacyPolicy:
                cell.configure(
                    icon: UIImage(systemName: "lock.doc.fill"),
                    title: "Privacy Policy",
                    accessoryStyle: .chevron
                )
            case .aboutApp:
                cell.configure(
                    icon: UIImage(systemName: "info.circle.fill"),
                    title: "About App",
                    accessoryStyle: .chevron
                )
            }
            return cell

        case .settings:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: "ProfileContentsTableViewCell",
                for: indexPath
            ) as? ProfileContentsTableViewCell,
            let row = SettingsRow(rawValue: indexPath.row) else {
                return UITableViewCell()
            }

            switch row {
            case .logOut:
                cell.configure(
                    icon: UIImage(systemName: "rectangle.portrait.and.arrow.right"),
                    title: "Log Out",
                    accessoryStyle: .none
                )
            case .deleteAccount:
                cell.configure(
                    icon: UIImage(systemName: "trash.fill"),
                    title: "Delete Account",
                    accessoryStyle: .none,
                    titleColor: .systemRed
                )
            }
            return cell
        }
    }

    override func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let section = Section(rawValue: indexPath.section) else { return }

        switch section {
        case .profile:
            break

        case .general:
            guard let row = GeneralRow(rawValue: indexPath.row) else { return }
            switch row {
            case .beasyPro:
                ProBenefitsViewController.present(from: self)
            case .upiCollection:
                navigationController?.pushViewController(UPICollectionSettingsViewController(), animated: true)
            case .gstSettings:
                let vc = GSTSettingsViewController()
                navigationController?.pushViewController(vc, animated: true)
            }

        case .reports:
            guard indexPath.row < currentReportsRows.count else { return }
            let row = currentReportsRows[indexPath.row]
            let reportType: ReportType
            switch row {
            case .byItem:
                reportType = .itemProfitability
            case .bySales:
                reportType = .salesRegister
            case .byCredit:
                reportType = .customerLedger
            case .gstr1:
                reportType = .gstr1
            case .gstr3b:
                reportType = .gstr3b
            }
            handleProfileReportTap(reportType)

        case .preferences:
            let rows = currentPreferencesRows
            guard indexPath.row < rows.count else { return }
            let row = rows[indexPath.row]
            switch row {
            case .appAppearance:
                presentAppearancePicker()
            case .dataBackup:
                exportDataBackup()
            case .cloudBackup:
                uploadCloudBackupTapped()
            case .importBackup:
                importDataBackup()
            case .restoreCloudBackup:
                restoreCloudBackupTapped()
            case .mobileSAM:
                break // Handled by toggle switch
            }

        case .legal:
            guard let row = LegalRow(rawValue: indexPath.row) else { return }
            switch row {
            case .termsAndConditions:
                showTermsAndConditions()
            case .privacyPolicy:
                showPrivacyPolicy()
            case .aboutApp:
                showAboutApp()
            }

        case .settings:
            guard let row = SettingsRow(rawValue: indexPath.row) else { return }
            switch row {
            case .logOut:
                logOutTapped()
            case .deleteAccount:
                deleteAccountTapped()
            }
        }
    }

    private func resolvedProfileName() -> String {
        let nameCandidates = [
            appSettings?.profileName,
            appSettings?.ownerName,
            appSettings?.businessName
        ]

        for candidate in nameCandidates {
            if let cleanValue = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !cleanValue.isEmpty {
                return cleanValue
            }
        }

        return ""
    }

    private func resolvedStoreName() -> String {
        appSettings?.businessName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func resolvedPhoneNumber() -> String? {
        guard let phone = appSettings?.businessPhone?.trimmingCharacters(in: .whitespacesAndNewlines),
              !phone.isEmpty else {
            return nil
        }
        return phone
    }

    private func resolvedAddress() -> String? {
        guard let address = appSettings?.businessAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty else { return nil }
        return address
    }

    private func resolvedGSTIN() -> String? {
        guard let gstin = appSettings?.gstNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
              !gstin.isEmpty else { return nil }
        return gstin
    }

    private func resolvedEmail() -> String? {
        let apple = AuthManager.shared.appleEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let apple, !apple.isEmpty { return apple }
        let stored = UserDefaults.standard.string(forKey: DefaultsKey.businessEmail)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }
        return nil
    }

    private func refreshEmailFromSupabase() {
        AuthManager.shared.fetchUserProfile { [weak self] profile in
            DispatchQueue.main.async {
                if let email = (profile?["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !email.isEmpty {
                    AuthManager.shared.saveAppleEmail(email)
                    self?.tableView.reloadSections(IndexSet(integer: Section.profile.rawValue), with: .none)
                    return
                }
                AuthManager.shared.fetchAuthUserEmail { authEmail in
                    DispatchQueue.main.async {
                        guard let authEmail, !authEmail.isEmpty else { return }
                        AuthManager.shared.saveAppleEmail(authEmail)
                        AuthManager.shared.updateUserProfile(name: nil, shopName: nil, phone: nil, email: authEmail)
                        self?.tableView.reloadSections(IndexSet(integer: Section.profile.rawValue), with: .none)
                    }
                }
            }
        }
    }

    private func resolvedWebsite() -> String? {
        let stored = UserDefaults.standard.string(forKey: DefaultsKey.businessWebsite)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }
        return nil
    }

    private func handleBusinessCardField(_ field: BusinessCardField) {
        switch field {
        case .shop:
            presentCardFieldEditor(
                title: "Shop name",
                placeholder: "Shop name",
                value: resolvedStoreName(),
                keyboard: .default,
                capitalization: .words
            ) { [weak self] text in
                guard let self, var settings = self.appSettings, let text, !text.isEmpty else { return }
                settings.businessName = text
                try? self.dataModel.db.updateSettings(settings)
                AuthManager.shared.updateUserProfile(name: nil, shopName: text, phone: nil)
            }
        case .owner:
            presentCardFieldEditor(
                title: "Owner name",
                placeholder: "Your name",
                value: resolvedProfileName(),
                keyboard: .default,
                capitalization: .words
            ) { [weak self] text in
                guard let self, var settings = self.appSettings, let text, !text.isEmpty else { return }
                settings.ownerName = text
                settings.profileName = text
                try? self.dataModel.db.updateSettings(settings)
                AuthManager.shared.updateUserProfile(name: text, shopName: nil, phone: nil)
            }
        case .phone:
            presentCardFieldEditor(
                title: "Mobile number",
                placeholder: "10-digit mobile",
                value: resolvedPhoneNumber(),
                keyboard: .phonePad,
                capitalization: .none
            ) { [weak self] text in
                guard let self, var settings = self.appSettings else { return }
                settings.businessPhone = text
                try? self.dataModel.db.updateSettings(settings)
                AuthManager.shared.updateUserProfile(name: nil, shopName: nil, phone: text)
            }
        case .address:
            presentCardFieldEditor(
                title: "Address",
                placeholder: "Shop address",
                value: resolvedAddress(),
                keyboard: .default,
                capitalization: .sentences
            ) { [weak self] text in
                guard let self, var settings = self.appSettings else { return }
                settings.businessAddress = text
                try? self.dataModel.db.updateSettings(settings)
            }
        case .gstin:
            presentCardFieldEditor(
                title: "GSTIN",
                placeholder: "15-character GSTIN",
                value: resolvedGSTIN(),
                keyboard: .asciiCapable,
                capitalization: .allCharacters
            ) { [weak self] text in
                guard let self, var settings = self.appSettings else { return }
                if let text, !text.isEmpty, !GSTEngine.isValidGSTIN(text) {
                    self.showSimpleInfo(title: "Invalid GSTIN", message: "Enter a valid 15-character GSTIN, or leave it blank.")
                    return
                }
                settings.gstNumber = text?.uppercased()
                try? self.dataModel.db.updateSettings(settings)
            }
        case .email:
            presentCardFieldEditor(
                title: "Email",
                placeholder: "shop@email.com",
                value: resolvedEmail(),
                keyboard: .emailAddress,
                capitalization: .none
            ) { text in
                if let text {
                    UserDefaults.standard.set(text, forKey: DefaultsKey.businessEmail)
                    AuthManager.shared.saveAppleEmail(text)
                    AuthManager.shared.updateUserProfile(name: nil, shopName: nil, phone: nil, email: text)
                } else {
                    UserDefaults.standard.removeObject(forKey: DefaultsKey.businessEmail)
                }
            }
        case .website:
            presentCardFieldEditor(
                title: "Website",
                placeholder: "www.yourshop.com",
                value: resolvedWebsite(),
                keyboard: .URL,
                capitalization: .none
            ) { text in
                if let text {
                    UserDefaults.standard.set(text, forKey: DefaultsKey.businessWebsite)
                } else {
                    UserDefaults.standard.removeObject(forKey: DefaultsKey.businessWebsite)
                }
            }
        }
    }

    private func presentCardFieldEditor(
        title: String,
        placeholder: String,
        value: String?,
        keyboard: UIKeyboardType,
        capitalization: UITextAutocapitalizationType,
        save: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(title: title, message: "This shows on your business card.", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = value
            textField.placeholder = placeholder
            textField.keyboardType = keyboard
            textField.autocapitalizationType = capitalization
            textField.autocorrectionType = .no
            textField.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            save(text?.isEmpty == true ? nil : text)
            self?.loadData()
            self?.tableView.reloadData()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func shareBusinessCard(image: UIImage) {
        var items: [Any] = [image]
        if let vcard = businessCardVCardURL() {
            items.append(vcard)
        }
        let text = businessCardShareText()
        if !text.isEmpty {
            items.append(text)
        }
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.minY + 80, width: 1, height: 1)
            popover.permittedArrowDirections = [.up]
        }
        present(activity, animated: true)
    }

    private func businessCardShareText() -> String {
        var lines: [String] = []
        let shop = resolvedStoreName()
        if !shop.isEmpty { lines.append(shop) }
        let owner = resolvedProfileName()
        if !owner.isEmpty { lines.append(owner) }
        if let phone = resolvedPhoneNumber() { lines.append(phone) }
        if let email = resolvedEmail() { lines.append(email) }
        if let address = resolvedAddress() { lines.append(address) }
        if let gstin = resolvedGSTIN() { lines.append("GSTIN \(gstin)") }
        if let website = resolvedWebsite() { lines.append(website) }
        return lines.joined(separator: "\n")
    }

    private func businessCardVCardURL() -> URL? {
        func vcardEscape(_ value: String) -> String {
            value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: ",", with: "\\,")
                .replacingOccurrences(of: ";", with: "\\;")
                .replacingOccurrences(of: "\n", with: "\\n")
        }
        var lines = ["BEGIN:VCARD", "VERSION:3.0"]
        let owner = resolvedProfileName()
        if !owner.isEmpty { lines.append("FN:\(vcardEscape(owner))") }
        let shop = resolvedStoreName()
        if !shop.isEmpty { lines.append("ORG:\(vcardEscape(shop))") }
        if let phone = resolvedPhoneNumber() { lines.append("TEL;TYPE=CELL:\(vcardEscape(phone))") }
        if let email = resolvedEmail() { lines.append("EMAIL:\(vcardEscape(email))") }
        if let address = resolvedAddress() { lines.append("ADR;TYPE=WORK:;;\(vcardEscape(address));;;;") }
        if let website = resolvedWebsite() { lines.append("URL:\(vcardEscape(website))") }
        if let gstin = resolvedGSTIN() { lines.append("NOTE:GSTIN \(vcardEscape(gstin))") }
        lines.append("END:VCARD")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("B-easy-card.vcf")
        do {
            try lines.joined(separator: "\r\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }


    private func profileImageTapped() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.allowsEditing = true

        let actionSheet = UIAlertController(title: "Profile Image", message: nil, preferredStyle: .actionSheet)

        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            actionSheet.addAction(UIAlertAction(title: "Choose Photo", style: .default) { _ in
                picker.sourceType = .photoLibrary
                self.present(picker, animated: true)
            })
        }

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            actionSheet.addAction(UIAlertAction(title: "Take Photo", style: .default) { _ in
                picker.sourceType = .camera
                self.present(picker, animated: true)
            })
        }

        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if appSettings?.profileImageData != nil {
            actionSheet.addAction(UIAlertAction(title: "Remove Photo", style: .destructive) { _ in
                guard var settings = self.appSettings else { return }
                settings.profileImageData = nil
                try? self.dataModel.db.updateSettings(settings)
                self.loadData()
                self.tableView.reloadData()
            })
        }

        if let popover = actionSheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }

        present(actionSheet, animated: true)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let selectedImage = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)

        if var settings = appSettings,
           let selectedImage,
           let imageData = selectedImage.jpegData(compressionQuality: 0.8) {
            settings.profileImageData = imageData
            try? dataModel.db.updateSettings(settings)
        }

        picker.dismiss(animated: true) {
            self.loadData()
            self.tableView.reloadData()
        }
    }

    private func currentAppearanceMode() -> AppearanceMode {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.appearanceMode) ?? AppearanceMode.system.rawValue
        return AppearanceMode(rawValue: raw) ?? .system
    }

    private func currentAppearanceTitle() -> String {
        switch currentAppearanceMode() {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    private func applySavedAppearance() {
        switch currentAppearanceMode() {
        case .system:
            view.window?.overrideUserInterfaceStyle = .unspecified
        case .light:
            view.window?.overrideUserInterfaceStyle = .light
        case .dark:
            view.window?.overrideUserInterfaceStyle = .dark
        }
    }

    private func presentAppearancePicker() {
        let alert = UIAlertController(title: "App Appearance", message: "Choose appearance mode.", preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "System", style: .default) { _ in
            self.setAppearanceMode(.system)
        })
        alert.addAction(UIAlertAction(title: "Light", style: .default) { _ in
            self.setAppearanceMode(.light)
        })
        alert.addAction(UIAlertAction(title: "Dark", style: .default) { _ in
            self.setAppearanceMode(.dark)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }

        present(alert, animated: true)
    }

    private func setAppearanceMode(_ mode: AppearanceMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKey.appearanceMode)
        applySavedAppearance()
        tableView.reloadData()
    }

    private func currentNotificationPreset() -> NotificationPreset {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.notificationPreset) ?? NotificationPreset.all.rawValue
        return NotificationPreset(rawValue: raw) ?? .all
    }

    private func currentNotificationPresetTitle() -> String {
        switch currentNotificationPreset() {
        case .all: return "All"
        case .essentials: return "Essentials"
        case .none: return "Off"
        }
    }

    private func presentNotificationPresetPicker() {
        let alert = UIAlertController(
            title: "Notification Control",
            message: "Choose which notifications you want.",
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: "All Notifications", style: .default) { _ in
            self.setNotificationPreset(.all)
        })
        alert.addAction(UIAlertAction(title: "Essentials Only", style: .default) { _ in
            self.setNotificationPreset(.essentials)
        })
        alert.addAction(UIAlertAction(title: "Turn Off", style: .destructive) { _ in
            self.setNotificationPreset(.none)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }

        present(alert, animated: true)
    }

    private func setNotificationPreset(_ preset: NotificationPreset) {
        UserDefaults.standard.set(preset.rawValue, forKey: DefaultsKey.notificationPreset)
        tableView.reloadData()
    }

    private func exportDataBackup() {
        presentLocalBackupShare()
    }

    private func presentLocalBackupShare(then continueAfter: (() -> Void)? = nil) {
        guard let backupURL = BackupService.shared.createBackup() else {
            showSimpleInfo(title: "Backup Failed", message: "Unable to create backup file.")
            return
        }

        let activityVC = UIActivityViewController(activityItems: [backupURL], applicationActivities: nil)
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            continueAfter?()
        }
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(activityVC, animated: true)
    }

    private func uploadCloudBackupTapped() {
        presentCloudBackup(then: nil)
    }

    private func presentCloudBackup(then continueAfter: (() -> Void)?) {
        let spinner = UIAlertController(title: "Uploading…", message: "Saving your ledger to the cloud.", preferredStyle: .alert)
        present(spinner, animated: true)
        CloudBackupService.shared.uploadLedger { [weak self] result in
            spinner.dismiss(animated: true) {
                switch result {
                case .success:
                    if let continueAfter {
                        continueAfter()
                    } else {
                        self?.showSimpleInfo(title: "Cloud Backup Saved", message: "Last upload: \(CloudBackupService.shared.lastSuccessDescription())")
                    }
                case .failure(let error):
                    self?.showSimpleInfo(title: "Cloud Backup Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func restoreCloudBackupTapped() {
        let confirm = UIAlertController(
            title: "Restore Cloud Backup?",
            message: "This replaces the ledger on this phone with the last file uploaded to the cloud.",
            preferredStyle: .alert
        )
        confirm.addAction(UIAlertAction(title: "Restore", style: .destructive) { [weak self] _ in
            self?.downloadAndRestoreCloudBackup()
        })
        confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(confirm, animated: true)
    }

    private func downloadAndRestoreCloudBackup() {
        let spinner = UIAlertController(title: "Restoring…", message: "Downloading your ledger from the cloud.", preferredStyle: .alert)
        present(spinner, animated: true)
        CloudBackupService.shared.downloadLedger { [weak self] result in
            switch result {
            case .failure(let error):
                spinner.dismiss(animated: true) {
                    self?.showSimpleInfo(title: "Restore Failed", message: error.localizedDescription)
                }
            case .success(let url):
                let ok = BackupService.shared.restoreBackup(from: url)
                spinner.dismiss(animated: true) {
                    if ok {
                        self?.showSimpleInfo(title: "Restored", message: "Cloud ledger restored. Restart the app if numbers look stale.")
                    } else {
                        self?.showSimpleInfo(title: "Restore Failed", message: "The downloaded file could not replace the local ledger.")
                    }
                }
            }
        }
    }

    private func showTermsAndConditions() {
        if let url = URL(string: "https://souravgupta2111.github.io/Ledgile/terms.html") {
            let safari = SFSafariViewController(url: url)
            present(safari, animated: true)
        }
    }

    private func showPrivacyPolicy() {
        if let url = URL(string: "https://souravgupta2111.github.io/Ledgile/privacy-policy.html") {
            let safari = SFSafariViewController(url: url)
            present(safari, animated: true)
        }
    }

    private func showAboutApp() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        showSimpleInfo(
            title: "About",
            message: "B-easy\nVersion \(version) (\(build))\nInventory, billing, and credit tracking for your store."
        )
    }

    private func showSimpleInfo(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }


    private func logOutTapped() {
        let alert = UIAlertController(
            title: "Log Out",
            message: "You can sign back in with the same number. Data on this phone stays until you delete the account.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Log Out", style: .destructive) { _ in
            AuthManager.shared.logOut()
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            guard let onboarding = storyboard.instantiateInitialViewController() else { return }
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.rootViewController = onboarding
                UIView.transition(with: window, duration: 0.35, options: .transitionCrossDissolve, animations: nil)
            }
        })
        present(alert, animated: true)
    }

    private func deleteAccountTapped() {
        let alert = UIAlertController(
            title: "Delete Account",
            message: "This will permanently delete your account and erase ALL local data. Back up to the cloud and save a local copy first. You cannot undo this.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Backup to Cloud, then Continue", style: .default) { [weak self] _ in
            self?.presentCloudBackup { self?.confirmAndDeleteAccount() }
        })
        alert.addAction(UIAlertAction(title: "Save Local Copy, then Continue", style: .default) { [weak self] _ in
            self?.presentLocalBackupShare { self?.confirmAndDeleteAccount() }
        })
        alert.addAction(UIAlertAction(title: "Delete Without Backup", style: .destructive) { [weak self] _ in
            self?.confirmAndDeleteAccount()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func confirmAndDeleteAccount() {
        let confirm = UIAlertController(
            title: "Are you absolutely sure?",
            message: "All your business data will be permanently deleted from this phone and your account will be removed.",
            preferredStyle: .alert
        )

        confirm.addAction(UIAlertAction(title: "Yes, Delete My Account", style: .destructive) { [weak self] _ in
            AuthManager.shared.deleteAccount { result in
                switch result {
                case .failure(let error):
                    let fail = UIAlertController(title: "Could not delete account", message: error.localizedDescription, preferredStyle: .alert)
                    fail.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(fail, animated: true)
                case .success:
                    if let sqliteDB = AppDataModel.shared.dataModel.db as? SQLiteDatabase {
                        sqliteDB.resetDatabase()
                    }

                    if let bundleId = Bundle.main.bundleIdentifier {
                        UserDefaults.standard.removePersistentDomain(forName: bundleId)
                    }

                    let storyboard = UIStoryboard(name: "Main", bundle: nil)
                    guard let onboardingNavController = storyboard.instantiateInitialViewController() else { return }

                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first {
                        window.rootViewController = onboardingNavController
                        UIView.transition(with: window, duration: 0.35, options: .transitionCrossDissolve, animations: nil, completion: nil)
                    }
                }
            }
        })

        confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(confirm, animated: true)
    }
}

// MARK: - Report Handling

extension ProfileTableViewController: QLPreviewControllerDataSource {

    func handleProfileReportTap(_ reportType: ReportType) {
        if reportType.needsDateRange {

            guard let picker = storyboard?.instantiateViewController(
                withIdentifier: "ReportDatePickerViewController"
            ) as? ReportDatePickerViewController else {
                return
            }

            picker.reportType = reportType
            picker.onGenerate = { [weak self] from, to in
                self?.generateAndShowReport(type: reportType, from: from, to: to)
            }

            picker.modalPresentationStyle = .pageSheet
            present(picker, animated: true)

        } else {
            let from = Calendar.current.date(byAdding: .year, value: -10, to: Date()) ?? Date()
            generateAndShowReport(type: reportType, from: from, to: Date())
        }
    }

    private func generateAndShowReport(type: ReportType, from: Date, to: Date) {
        guard let pdfURL = ReportGenerator.shared.generateReport(type: type, from: from, to: to) else {
            showSimpleInfo(title: "Error", message: "Failed to generate report.")
            return
        }

        let item = PDFPreviewItem(url: pdfURL, name: type.rawValue)
        pdfPreviewDataSource = PDFPreviewDataSource(item: item)

        let ql = QLPreviewController()
        ql.dataSource = self
        present(ql, animated: true)
    }

    // QLPreviewControllerDataSource
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        pdfPreviewDataSource?.item ?? PDFPreviewItem(url: URL(fileURLWithPath: ""), name: "")
    }
}

// MARK: - Import Backup

extension ProfileTableViewController: UIDocumentPickerDelegate {

    func importDataBackup() {
        let alert = UIAlertController(
            title: "Import Backup",
            message: "This will replace ALL current data with the data from the backup file. Are you sure?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Choose File", style: .default) { [weak self] _ in
            self?.presentDocumentPicker()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func presentDocumentPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let fileURL = urls.first else { return }

        // Verify it's a sqlite file
        let ext = fileURL.pathExtension.lowercased()
        guard ext == "sqlite" || ext == "db" || ext == "sqlite3" else {
            showSimpleInfo(title: "Invalid File", message: "Please select a .sqlite backup file exported from B-easy.")
            return
        }

        let success = BackupService.shared.restoreBackup(from: fileURL)
        if success {
            // Refresh everything
            let alert = UIAlertController(
                title: "Restore Complete",
                message: "Your data has been restored from the backup. The app will now reload.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
                self?.loadData()
                self?.tableView.reloadData()
                // Post notification so other tabs refresh
                NotificationCenter.default.post(name: NSNotification.Name("BackupRestored"), object: nil)
            })
            present(alert, animated: true)
        } else {
            showSimpleInfo(title: "Restore Failed", message: "Unable to restore this backup file. It may be corrupted or invalid.")
        }
    }
}
