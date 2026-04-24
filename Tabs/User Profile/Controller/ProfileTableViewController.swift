import UIKit
import QuickLook

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
        case storeName
        case gstSettings
        case support
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
        case notificationControl
        case dataBackup
        case importBackup
    }

    private enum LegalRow: Int, CaseIterable {
        case termsAndConditions
        case privacyPolicy
        case aboutApp
    }

    private enum SettingsRow: Int, CaseIterable {
        case pushNotification
        case faceID
        case pinCode
        case logOut
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
        static let faceIDEnabled = "profile.settings.faceid.enabled"
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
        case .reports: return currentReportsRows.count
        case .preferences: return PreferencesRow.allCases.count
        case .legal: return LegalRow.allCases.count
        case .settings: return SettingsRow.allCases.count
        }
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let section = Section(rawValue: indexPath.section) else { return 50 }
        return section == .profile ? 250 : 50
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .profile: return nil
        case .general: return "General"
        case .reports: return "Reports"
        case .preferences: return "Preferences"
        case .legal: return "Legal"
        case .settings: return "Settings"
        }
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard let sectionType = Section(rawValue: section) else { return 36 }
        return sectionType == .profile ? 0.01 : 36
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

            let image = appSettings?.profileImageData.flatMap { UIImage(data: $0) }
            cell.configure(name: resolvedProfileName(), phone: resolvedPhoneNumber(), image: image)
            cell.onEditProfileTapped = { [weak self] in
                self?.editProfileTapped()
            }
            cell.onImageTapped = { [weak self] in
                self?.profileImageTapped()
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
            case .storeName:
                cell.configure(
                    icon: UIImage(systemName: "storefront.fill"),
                    title: "Store Name: \(resolvedStoreName())",
                    accessoryStyle: .chevron
                )
            case .gstSettings:
                let gstStatus = (appSettings?.isGSTRegistered ?? false) ? "Enabled" : "Disabled"
                cell.configure(
                    icon: UIImage(systemName: "percent"),
                    title: "GST Settings (\(gstStatus))",
                    accessoryStyle: .chevron
                )
            case .support:
                cell.configure(
                    icon: UIImage(systemName: "headphones"),
                    title: "Support",
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
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: "ProfileContentsTableViewCell",
                for: indexPath
            ) as? ProfileContentsTableViewCell,
            let row = PreferencesRow(rawValue: indexPath.row) else {
                return UITableViewCell()
            }

            switch row {
            case .appAppearance:
                cell.configure(
                    icon: UIImage(systemName: "paintbrush.fill"),
                    title: "App Appearance: \(currentAppearanceTitle())",
                    accessoryStyle: .chevron
                )
            case .notificationControl:
                cell.configure(
                    icon: UIImage(systemName: "bell.badge.fill"),
                    title: "Notification Control: \(currentNotificationPresetTitle())",
                    accessoryStyle: .chevron
                )
            case .dataBackup:
                cell.configure(
                    icon: UIImage(systemName: "tray.and.arrow.up.fill"),
                    title: "Data Backup",
                    accessoryStyle: .chevron
                )
            case .importBackup:
                cell.configure(
                    icon: UIImage(systemName: "tray.and.arrow.down.fill"),
                    title: "Import Backup",
                    accessoryStyle: .chevron
                )
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
            case .pushNotification:
                cell.configure(
                    icon: UIImage(systemName: "bell.fill"),
                    title: "Push Notification",
                    accessoryStyle: .toggle(isOn: pushNotificationsEnabled())
                )
                cell.onToggleChanged = { isOn in
                    UserDefaults.standard.set(isOn, forKey: DefaultsKey.pushEnabled)
                }

            case .faceID:
                cell.configure(
                    icon: UIImage(systemName: "faceid"),
                    title: "Face ID",
                    accessoryStyle: .toggle(isOn: faceIDEnabled())
                )
                cell.onToggleChanged = { isOn in
                    UserDefaults.standard.set(isOn, forKey: DefaultsKey.faceIDEnabled)
                }

            case .pinCode:
                cell.configure(
                    icon: UIImage(systemName: "circle.grid.3x3.fill"),
                    title: "PIN Code",
                    accessoryStyle: .chevron
                )

            case .logOut:
                cell.configure(
                    icon: UIImage(systemName: "rectangle.portrait.and.arrow.right"),
                    title: "Log Out",
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
            case .storeName:
                editStoreNameTapped()
            case .gstSettings:
                let vc = GSTSettingsViewController()
                navigationController?.pushViewController(vc, animated: true)
            case .support:
                showSimpleInfo(title: "Support", message: "Contact support from this section.")
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
            guard let row = PreferencesRow(rawValue: indexPath.row) else { return }
            switch row {
            case .appAppearance:
                presentAppearancePicker()
            case .notificationControl:
                presentNotificationPresetPicker()
            case .dataBackup:
                exportDataBackup()
            case .importBackup:
                importDataBackup()
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
            case .pushNotification:
                break
            case .faceID:
                break
            case .pinCode:
                showSimpleInfo(title: "PIN Code", message: "PIN setup screen can be added here.")
            case .logOut:
                logOutTapped()
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

        return "User"
    }

    private func resolvedStoreName() -> String {
        let value = appSettings?.businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty {
            return value
        }
        return "My Store"
    }

    private func resolvedPhoneNumber() -> String? {
        guard let phone = appSettings?.businessPhone?.trimmingCharacters(in: .whitespacesAndNewlines),
              !phone.isEmpty else {
            return nil
        }
        return phone
    }

    private func pushNotificationsEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: DefaultsKey.pushEnabled) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: DefaultsKey.pushEnabled)
    }

    private func faceIDEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: DefaultsKey.faceIDEnabled) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: DefaultsKey.faceIDEnabled)
    }

    private func editProfileTapped() {
        let currentName = resolvedProfileName()
        let currentPhone = resolvedPhoneNumber()

        let alert = UIAlertController(
            title: "Edit Profile",
            message: "Update your name and mobile number.",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.text = currentName
            textField.placeholder = "Name"
            textField.autocapitalizationType = .words
            textField.clearButtonMode = .whileEditing
        }

        alert.addTextField { textField in
            textField.text = currentPhone
            textField.placeholder = "Mobile number"
            textField.keyboardType = .phonePad
            textField.clearButtonMode = .whileEditing
        }

        let saveAction = UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self = self, var settings = self.appSettings else { return }

            let newName = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let newPhone = alert.textFields?.dropFirst().first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let newName, !newName.isEmpty {
                settings.ownerName = newName
                settings.profileName = newName
            }

            settings.businessPhone = newPhone
            try? self.dataModel.db.updateSettings(settings)
            self.loadData()
            self.tableView.reloadData()
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

        alert.addAction(saveAction)
        alert.addAction(cancelAction)

        present(alert, animated: true)
    }

    private func editStoreNameTapped() {
        let alert = UIAlertController(
            title: "Edit Store Name",
            message: "Update your store name.",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.text = self.resolvedStoreName()
            textField.placeholder = "Store name"
            textField.autocapitalizationType = .words
            textField.clearButtonMode = .whileEditing
        }

        let saveAction = UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self = self, var settings = self.appSettings else { return }

            let newStoreName = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let newStoreName, !newStoreName.isEmpty else { return }

            settings.businessName = newStoreName
            try? self.dataModel.db.updateSettings(settings)
            self.loadData()
            self.tableView.reloadData()
        }

        alert.addAction(saveAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
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
        guard let backupURL = BackupService.shared.createBackup() else {
            showSimpleInfo(title: "Backup Failed", message: "Unable to create backup file.")
            return
        }

        let activityVC = UIActivityViewController(activityItems: [backupURL], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(activityVC, animated: true)
    }

    private func showTermsAndConditions() {
        showSimpleInfo(
            title: "Terms & Conditions",
            message: "By using this app, you agree to use it responsibly and keep your business data accurate. You are responsible for local tax and legal compliance."
        )
    }

    private func showPrivacyPolicy() {
        showSimpleInfo(
            title: "Privacy Policy",
            message: "Your data is stored locally on your device. Backups you export are controlled by you. Do not share backup files with untrusted parties."
        )
    }

    private func showAboutApp() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        showSimpleInfo(
            title: "About",
            message: "Tabs\nVersion \(version) (\(build))\nInventory, billing, and credit tracking for your store."
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
            message: "Confirm Log Out",
            preferredStyle: .alert
        )

        let logOutAction = UIAlertAction(title: "Log Out", style: .destructive) { _ in
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            guard let onboardingNavController = storyboard.instantiateInitialViewController() else { return }

            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.rootViewController = onboardingNavController
                UIView.transition(with: window, duration: 0.35, options: .transitionCrossDissolve, animations: nil, completion: nil)
            }
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

        alert.addAction(logOutAction)
        alert.addAction(cancelAction)

        present(alert, animated: true)
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
            showSimpleInfo(title: "Invalid File", message: "Please select a .sqlite backup file exported from Ledgile.")
            return
        }

        let success = BackupService.shared.restoreBackup(from: fileURL)
        if success {
            // Refresh everything
            let alert = UIAlertController(
                title: "Restore Complete ✅",
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
