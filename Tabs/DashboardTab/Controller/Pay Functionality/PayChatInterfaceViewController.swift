import UIKit
protocol SupplierDeleteDelegate: AnyObject {
    func didDeleteSupplier(_ supplier: Supplier)
    func didUpdateSupplier(_ supplier: Supplier)
}
class PayChatInterfaceViewController: UIViewController {
    var supplier: Supplier?

    weak var delegate: SupplierDeleteDelegate?
    
    @IBOutlet weak var youPayLabel: UILabel!
    @IBOutlet weak var tableView: UITableView!
    
    var transactions: [SupplierPayment] = []
    var isNewCustomer: Bool = false
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = supplier?.name
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.backgroundColor = .systemGray6
        
        tableView.register(UINib(nibName: "ReceivedTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "ReceivedTableViewCell")
        tableView.register(UINib(nibName: "PaidTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "PaidTableViewCell")
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.clipsToBounds = true
        tableView.transform = CGAffineTransform(scaleX: 1, y: -1)
        
        tableView.separatorStyle = .none
        loadTransactions()
        updateBalance()
    }
    
    private func loadTransactions() {
        guard let supplierID = supplier?.id else { return }
        // Load real transactions from CreditStore, reversed so newest is at index 0
        transactions = CreditStore.shared.getPayments(forSupplier: supplierID).reversed()
        tableView.reloadData()
    }
    
    private func updateBalance() {
        guard let supplierID = supplier?.id else { return }
        let balance = CreditStore.shared.getNetBalance(forSupplier: supplierID)
        
        if balance > 0 {
            // You owe them
            youPayLabel.text = "You'll pay ₹\(Int(balance))"
            youPayLabel.textColor = .systemRed
        } else if balance < 0 {
            // They owe you
            youPayLabel.text = "You'll receive ₹\(Int(-balance))"
            youPayLabel.textColor = UIColor(named: "Lime Moss")!
        } else {
            youPayLabel.text = "Balance ₹0"
            youPayLabel.textColor = .secondaryLabel
        }
        
        // Update the supplier's balance and notify parent
        supplier?.netBalance = balance
        if let supplier = supplier {
            delegate?.didUpdateSupplier(supplier)
        }
    }
    
    private func scrollToBottom() {
        guard !transactions.isEmpty else { return }
        let indexPath = IndexPath(row: 0, section: 0)
        tableView.scrollToRow(at: indexPath, at: .top, animated: true)
    }
    
    @IBAction func editButtonTapped(_ sender: UIBarButtonItem) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let vc = storyboard.instantiateViewController(
                withIdentifier: "EditProfileViewController"
            ) as! EditProfileViewController

        vc.name = supplier?.name
        vc.phone = supplier?.phone
        vc.delegate = self
        
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet

        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }

            present(nav, animated: true)
    }
    
    @IBAction func deleteButtonTapped(_ sender: UIBarButtonItem) {
        guard let supplier = supplier else { return }
            
        let alert = UIAlertController(
            title: "Delete Contact",
            message: "Are you sure you want to delete this contact? All transaction history will be lost.",
            preferredStyle: .alert
        )
            
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            self.delegate?.didDeleteSupplier(supplier)
            self.navigationController?.popViewController(animated: true)
        })
            
        present(alert, animated: true)
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "AddPayTransactionSegue" {
            if let addVC = segue.destination as? PayAddTransactionViewController {
                addVC.supplierID = supplier?.id
                addVC.delegate = self
            }
        }
    }
}

extension PayChatInterfaceViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        transactions.count
    }
    
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let transaction = transactions[indexPath.row]
        let formattedDate = dateFormatter.string(from: transaction.date)
        
        if transaction.type == .received {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: "ReceivedTableViewCell",
                for: indexPath
            ) as! ReceivedTableViewCell
            cell.contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
            cell.amountLabel.text = "₹\(Int(transaction.amount))"
            cell.dateLabel.text = "Bought on \(formattedDate)"
            cell.amountLabel.textColor = .systemRed
            
            // Check for linked bill in note
            if let note = transaction.note, note.localizedCaseInsensitiveContains("Credit purchase") {
                let cleanedInvoice = note.replacingOccurrences(of: "Credit purchase", with: "", options: .caseInsensitive)
                                         .replacingOccurrences(of: ":", with: "")
                                         .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !cleanedInvoice.isEmpty {
                    cell.chevronButton.isHidden = false
                    cell.tapAction = { [weak self] in
                        self?.showBill(for: cleanedInvoice)
                    }
                } else {
                    cell.chevronButton.isHidden = true
                }
            } else {
                cell.chevronButton.isHidden = true
            }

            return cell
            
        } else {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: "PaidTableViewCell",
                for: indexPath
            ) as! PaidTableViewCell
            cell.contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
            cell.amountLabel.text = "₹\(Int(transaction.amount))"
            cell.dateLabel.text = "Paid on \(formattedDate)"
            cell.amountLabel.textColor = UIColor(named: "Lime Moss")!
            
            cell.chevronButton.isHidden = true
            cell.tapAction = nil
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let cell = tableView.cellForRow(at: indexPath)
        if let receivedCell = cell as? ReceivedTableViewCell {
            receivedCell.tapAction?()
        } else if let paidCell = cell as? PaidTableViewCell {
            paidCell.tapAction?()
        }
    }

    private func showBill(for invoiceNumber: String) {
        let dm = AppDataModel.shared.dataModel
        let target = invoiceNumber.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        let allTx = (try? dm.db.getTransactions()) ?? []
        guard let transaction = allTx.first(where: { 
            $0.type == TransactionType.purchase && $0.invoiceNumber.lowercased().contains(target) 
        }) else { return }
        
        presentBillSheet(for: transaction)
    }


}
extension PayChatInterfaceViewController: AddPayTransactionDelegate {
    func didAddTransaction(_ transaction: SupplierPayment) {
        // Save to CreditStore
        CreditStore.shared.addSupplierPayment(transaction)
        
        // Reload from store
        loadTransactions()
        updateBalance()
        scrollToBottom()
    }
}

extension PayChatInterfaceViewController: EditProfileDelegate {
    func didUpdateProfile(name: String?, phone: String?, image: UIImage?) {
        supplier?.name = name ?? "Unknown"
        supplier?.phone = phone
        supplier?.profileImage = image
        
        if let supplier = supplier {
            CreditStore.shared.updateSupplier(supplier)
            delegate?.didUpdateSupplier(supplier)
        }
        
        title = name
    }
}
