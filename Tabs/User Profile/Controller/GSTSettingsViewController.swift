// GSTSettingsViewController.swift
// UI for configuring GST preferences

import UIKit

class GSTSettingsViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case registration
        case details
        case defaults
    }

    private var appSettings: AppSettings

    private lazy var gstRegisteredSwitch: UISwitch = {
        let sw = UISwitch()
        sw.addTarget(self, action: #selector(gstRegisteredChanged(_:)), for: .valueChanged)
        return sw
    }()
    
    private lazy var pricesIncludeGSTSwitch: UISwitch = {
        let sw = UISwitch()
        sw.addTarget(self, action: #selector(pricesIncludeGSTChanged(_:)), for: .valueChanged)
        return sw
    }()

    init() {
        self.appSettings = (try? AppDataModel.shared.dataModel.db.getSettings()) ?? AppSettings(
            invoicePrefix: "INV", invoiceNumberCounter: 1, includeYearInInvoice: false,
            businessName: "My Shop", expiryNoticeDays: 14, expiryWarningDays: 7, expiryCriticalDays: 3
        )
        super.init(style: .grouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "GST Settings"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        
        gstRegisteredSwitch.isOn = appSettings.isGSTRegistered
        pricesIncludeGSTSwitch.isOn = appSettings.pricesIncludeGST
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(saveTapped))
    }

    @objc private func gstRegisteredChanged(_ sender: UISwitch) {
        appSettings.isGSTRegistered = sender.isOn
        tableView.reloadData()
    }
    
    @objc private func pricesIncludeGSTChanged(_ sender: UISwitch) {
        appSettings.pricesIncludeGST = sender.isOn
    }

    @objc private func saveTapped() {
        // Validate GSTIN if registered
        if appSettings.isGSTRegistered {
            if let gstin = appSettings.gstNumber, !gstin.isEmpty {
                if !GSTEngine.isValidGSTIN(gstin) {
                    let alert = UIAlertController(title: "Invalid GSTIN", message: "Please enter a valid 15-character GSTIN.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    present(alert, animated: true)
                    return
                }
                
                // Auto-fill state if empty based on GSTIN
                if (appSettings.businessStateCode == nil || appSettings.businessStateCode?.isEmpty == true) {
                    if let state = IndianStates.stateFromGSTIN(gstin) {
                        appSettings.businessState = state.name
                        appSettings.businessStateCode = state.code
                    }
                }
            }
        }
        
        do {
            try AppDataModel.shared.dataModel.db.updateSettings(appSettings)
            navigationController?.popViewController(animated: true)
        } catch {
            let alert = UIAlertController(title: "Error", message: "Failed to save settings: \(error.localizedDescription)", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return appSettings.isGSTRegistered ? Section.allCases.count : 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let s = Section(rawValue: section) else { return 0 }
        switch s {
        case .registration: return 1
        case .details: return 3 // GSTIN, State, Scheme
        case .defaults: return 2 // MRP includes GST, Default GST Rate
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let s = Section(rawValue: section) else { return nil }
        switch s {
        case .registration: return "GST Registration"
        case .details: return "Business Details"
        case .defaults: return "Invoice Defaults"
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let s = Section(rawValue: section) else { return nil }
        switch s {
        case .registration:
            return appSettings.isGSTRegistered ? nil : "Enable this to generate GST-compliant invoices and file returns."
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "cell")
        cell.selectionStyle = .none
        cell.accessoryView = nil
        cell.accessoryType = .none
        
        guard let s = Section(rawValue: indexPath.section) else { return cell }
        
        switch s {
        case .registration:
            cell.textLabel?.text = "I am GST Registered"
            cell.accessoryView = gstRegisteredSwitch
            
        case .details:
            cell.selectionStyle = .default
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "GSTIN"
                cell.detailTextLabel?.text = appSettings.gstNumber?.isEmpty == false ? appSettings.gstNumber : "Not Set"
                cell.accessoryType = .disclosureIndicator
            case 1:
                cell.textLabel?.text = "Business State"
                cell.detailTextLabel?.text = appSettings.businessState?.isEmpty == false ? appSettings.businessState : "Select"
                cell.accessoryType = .disclosureIndicator
            case 2:
                cell.textLabel?.text = "Registration Scheme"
                let schemeTitle = (appSettings.gstScheme == "composition") ? "Composition" : "Regular"
                cell.detailTextLabel?.text = schemeTitle
                cell.accessoryType = .disclosureIndicator
            default: break
            }
            
        case .defaults:
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Item Prices Include GST (MRP)"
                cell.textLabel?.adjustsFontSizeToFitWidth = true
                cell.accessoryView = pricesIncludeGSTSwitch
            case 1:
                cell.selectionStyle = .default
                cell.textLabel?.text = "Default GST Rate"
                if let rate = appSettings.defaultGSTRate {
                    cell.detailTextLabel?.text = "\(rate) %"
                } else {
                    cell.detailTextLabel?.text = "None"
                }
                cell.accessoryType = .disclosureIndicator
            default: break
            }
        }
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let s = Section(rawValue: indexPath.section) else { return }
        
        if s == .details {
            switch indexPath.row {
            case 0:
                promptForGSTIN()
            case 1:
                promptForState()
            case 2:
                promptForScheme()
            default: break
            }
        } else if s == .defaults {
            if indexPath.row == 1 {
                promptForDefaultGSTRate()
            }
        }
    }
    
    // MARK: - Prompts
    
    private func promptForGSTIN() {
        let alert = UIAlertController(title: "GSTIN", message: "Enter your 15-character GSTIN", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "e.g. 29ABCDE1234F1Z5"
            tf.text = self.appSettings.gstNumber
            tf.autocapitalizationType = .allCharacters
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { _ in
            let input = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            self.appSettings.gstNumber = input
            
            // Auto-extract state code if valid
            if let gstin = input, GSTEngine.isValidGSTIN(gstin), let state = IndianStates.stateFromGSTIN(gstin) {
                self.appSettings.businessState = state.name
                self.appSettings.businessStateCode = state.code
            }
            
            self.tableView.reloadData()
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func promptForState() {
        let alert = UIAlertController(title: "Business State", message: "Select the state where your business is registered.", preferredStyle: .actionSheet)
        
        let states = IndianStates.sortedNames
        for stateName in states {
            alert.addAction(UIAlertAction(title: stateName, style: .default, handler: { _ in
                if let state = IndianStates.stateByName(stateName) {
                    self.appSettings.businessState = state.name
                    self.appSettings.businessStateCode = state.code
                    self.tableView.reloadData()
                }
            }))
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        present(alert, animated: true)
    }
    
    private func promptForScheme() {
        let alert = UIAlertController(title: "GST Scheme", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Regular", style: .default, handler: { _ in
            self.appSettings.gstScheme = "regular"
            self.tableView.reloadData()
        }))
        alert.addAction(UIAlertAction(title: "Composition", style: .default, handler: { _ in
            self.appSettings.gstScheme = "composition"
            self.tableView.reloadData()
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        present(alert, animated: true)
    }
    
    private func promptForDefaultGSTRate() {
        let alert = UIAlertController(title: "Default GST Rate", message: "Applied automatically if item doesn't have a specific rate.", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "None", style: .default, handler: { _ in
            self.appSettings.defaultGSTRate = nil
            self.tableView.reloadData()
        }))
        
        for rate in IndianStates.validGSTRates {
            alert.addAction(UIAlertAction(title: "\(rate) %", style: .default, handler: { _ in
                self.appSettings.defaultGSTRate = rate
                self.tableView.reloadData()
            }))
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        present(alert, animated: true)
    }
}
