//  Manual purchase entry with product training video for CLIP embeddings.

import UIKit

protocol PurchaseItemInformationDelegate: AnyObject {
    func itemInformation(
        _ controller: PurchaseItemInformationTableViewController,
        entry: PurchaseEntry
    )
}

class PurchaseItemInformationTableViewController: UITableViewController {
    
    private var entry = PurchaseEntry()
    
    weak var delegate: PurchaseItemInformationDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.backgroundColor = UIColor.systemGray6
        
        tableView.register(UINib(nibName: "LabelTextFieldTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "LabelTextFieldTableViewCell")
        tableView.register(UINib(nibName: "LabelDatePickerTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "LabelDatePickerTableViewCell")
    }
    
    // MARK: - Done
    
    @IBAction func doneButtonTapped(_ sender: UIBarButtonItem) {
        let itemName = (entry.selectedItemName ?? "").trimmingCharacters(in: .whitespaces)

        if itemName.isEmpty {
            showAlert(title: "Missing Item", message: "Please select an item.")
            return
        }

        if entry.quantity <= 0 {
            showAlert(title: "Invalid Quantity", message: "Enter quantity greater than 0.")
            return
        }

        if entry.costPrice <= 0 {
            showAlert(title: "Missing Cost Price", message: "Enter cost price.")
            return
        }

        delegate?.itemInformation(self, entry: entry)
        navigationController?.popViewController(animated: true)
    }
    
    @IBAction func closeButtonTapped(_ sender: UIBarButtonItem) {
        navigationController?.popViewController(animated: true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - TableView

extension PurchaseItemInformationTableViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 8
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0.01
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        switch indexPath.row {

        case 0:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: "rightDetail")
            cell.textLabel?.text = "Item"
            cell.textLabel?.textColor = .systemRed
            
            if let name = entry.selectedItemName, !name.isEmpty {
                cell.detailTextLabel?.text = name
            } else {
                cell.detailTextLabel?.text = "Tap to Select"
                cell.detailTextLabel?.textColor = .systemGray2
            }
            
            cell.accessoryType = .disclosureIndicator
            return cell

        case 1:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: "rightDetail")
            cell.textLabel?.text = "Unit"
            
            if let unit = entry.selectedUnitName, !unit.isEmpty {
                cell.detailTextLabel?.text = unit
            } else {
                cell.detailTextLabel?.text = "Tap to Select"
                cell.detailTextLabel?.textColor = .systemGray2
            }
            
            cell.accessoryType = .disclosureIndicator
            return cell

        case 2:
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            cell.titleLabel.text = "Quantity"
            cell.titleLabel.textColor = .systemRed
            cell.textField.placeholder = "0"
            cell.textField.text = entry.quantity > 0 ? String(entry.quantity) : ""
            
            cell.onTextChanged = { [weak self] text in
                self?.entry.quantity = Double(text) ?? 0
            }
            return cell

        case 3:
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            cell.titleLabel.text = "Selling Price"
            cell.titleLabel.textColor = .systemRed
            cell.textField.placeholder = "₹ 0.00"
            cell.textField.text = entry.sellingPrice > 0 ? String(entry.sellingPrice) : ""
            
            cell.onTextChanged = { [weak self] text in
                self?.entry.sellingPrice = Double(text) ?? 0
            }
            return cell

        case 4:
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            cell.titleLabel.text = "Cost Price"
            cell.textField.placeholder = "₹ 0.00"
            cell.textField.text = entry.costPrice > 0 ? String(entry.costPrice) : ""
            
            cell.onTextChanged = { [weak self] text in
                self?.entry.costPrice = Double(text) ?? 0
            }
            return cell

        case 5:
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelTextFieldTableViewCell", for: indexPath) as! LabelTextFieldTableViewCell
            cell.titleLabel.text = "Low Stock Alert"
            cell.textField.placeholder = "Enter count"
            cell.textField.text = entry.lowStockThreshold > 0 ? String(entry.lowStockThreshold) : ""
            
            cell.onTextChanged = { [weak self] text in
                self?.entry.lowStockThreshold = Int(text) ?? 0
            }
            return cell

        case 6:
            let cell = tableView.dequeueReusableCell(withIdentifier: "LabelDatePickerTableViewCell", for: indexPath) as! LabelDatePickerTableViewCell
            cell.titleLabel.text = "Expiry Date"
            cell.datePicker.date = entry.expiryDate
            
            cell.onDateChanged = { [weak self] date in
                self?.entry.expiryDate = date
            }
            return cell

        case 7:
            let cell = UITableViewCell()
            cell.selectionStyle = .none
            
            // Title: "Photo of Item"
            let titleLabel = UILabel()
            titleLabel.text = "Photo of Item"
            titleLabel.font = .systemFont(ofSize: 17)
            titleLabel.textColor = .label
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(titleLabel)
            
            // Add Photo button
            let addPhotoBtn = UIButton(type: .system)
            let cameraConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            addPhotoBtn.setImage(UIImage(systemName: "camera.badge.ellipsis", withConfiguration: cameraConfig), for: .normal)
            addPhotoBtn.setTitle("Add Photo", for: .normal)
            addPhotoBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            addPhotoBtn.addTarget(self, action: #selector(addPhotoTapped), for: .touchUpInside)
            addPhotoBtn.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(addPhotoBtn)
            
            // Record button
            let recordBtn = UIButton(type: .system)
            let recordConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            recordBtn.setImage(UIImage(systemName: "record.circle", withConfiguration: recordConfig), for: .normal)
            recordBtn.setTitle("Record", for: .normal)
            recordBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            recordBtn.addTarget(self, action: #selector(recordTrainingVideoTapped), for: .touchUpInside)
            recordBtn.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(recordBtn)
            
            // Subtitle
            let subtitle = UILabel()
            if entry.pendingItemPhotos.isEmpty {
                subtitle.text = "Add photos or record 5–8s video for object detection"
            } else {
                subtitle.text = "\(entry.pendingItemPhotos.count) frames captured"
            }
            subtitle.font = .systemFont(ofSize: 13)
            subtitle.textColor = entry.pendingItemPhotos.isEmpty ? .secondaryLabel : UIColor(named: "Lime Moss")!
            subtitle.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(subtitle)
            
            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 10),
                titleLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                
                addPhotoBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
                addPhotoBtn.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
                
                recordBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
                recordBtn.leadingAnchor.constraint(equalTo: addPhotoBtn.trailingAnchor, constant: 16),
                recordBtn.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
                
                subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
                subtitle.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                subtitle.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
                subtitle.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -10),
            ])
            
            return cell

        default:
            return UITableViewCell()
        }
    }
}

// MARK: - Selection

extension PurchaseItemInformationTableViewController {
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.row == 0 {
            performSegue(withIdentifier: "item_selection", sender: nil)
        } else if indexPath.row == 1 {
            performSegue(withIdentifier: "unit_selection", sender: nil)
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "item_selection",
           let dest = segue.destination as? PurchaseItemSelectionTableViewController {
            dest.delegate = self
        }
        else if segue.identifier == "unit_selection",
                let dest = segue.destination as? PurchaseUnitSelectionTableViewController {
            dest.unitDelegate = self
        }
    }
}

// MARK: - Delegates

extension PurchaseItemInformationTableViewController: PurchaseItemSelectionDelegate {
    func itemSelection(_ controller: PurchaseItemSelectionTableViewController, didSelectItem item: String) {
        entry.selectedItemName = item
        tableView.reloadData()
    }
}

extension PurchaseItemInformationTableViewController: PurchaseUnitSelectionDelegate {
    func unitSelection(_ controller: PurchaseUnitSelectionTableViewController, unit: String) {
        entry.selectedUnitName = unit
        tableView.reloadData()
    }
}

// MARK: - Training Video Recording

extension PurchaseItemInformationTableViewController {

    @objc private func recordTrainingVideoTapped() {
        let vc = InventoryCaptureVideoViewController()
        vc.onComplete = { [weak self] images in
            guard let self = self, !images.isEmpty else { return }
            self.entry.pendingItemPhotos.append(contentsOf: images)
            print("[Purchase] Recorded \(images.count) training frames from video (total: \(self.entry.pendingItemPhotos.count))")

            // If item is already selected, trigger embedding update
            if let itemName = self.entry.selectedItemName, !itemName.isEmpty {
                let allItems = (try? AppDataModel.shared.dataModel.db.getAllItems()) ?? []
                if let item = allItems.first(where: { $0.name == itemName }) {
                    ProductFingerprintManager.shared.updateEmbeddings(for: item.id) {
                        print("[Purchase] Updated CLIP embeddings for \(itemName)")
                    }
                }
            }

            // Refresh row 7 to show frame count
            DispatchQueue.main.async {
                self.tableView.reloadRows(at: [IndexPath(row: 7, section: 0)], with: .automatic)
            }
        }
        vc.onCancel = { /* nothing */ }
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    @objc private func addPhotoTapped() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Take Photo", style: .default) { [weak self] _ in
            self?.presentCamera()
        })
        alert.addAction(UIAlertAction(title: "Choose from Library", style: .default) { [weak self] _ in
            self?.presentPhotoPicker()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        present(picker, animated: true)
    }

    private func presentPhotoPicker() {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        present(picker, animated: true)
    }
}

// MARK: - Photo Picker Delegate

extension PurchaseItemInformationTableViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        if let image = info[.originalImage] as? UIImage {
            // Compress for small storage
            let maxDim: CGFloat = 480
            let scale = min(maxDim / max(image.size.width, image.size.height), 1.0)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resized = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            if let compressed = resized?.jpegData(compressionQuality: 0.7),
               let final = UIImage(data: compressed) {
                entry.pendingItemPhotos.append(final)
            } else {
                entry.pendingItemPhotos.append(image)
            }
            print("[Purchase] Added photo (total: \(entry.pendingItemPhotos.count))")
            tableView.reloadRows(at: [IndexPath(row: 7, section: 0)], with: .automatic)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
