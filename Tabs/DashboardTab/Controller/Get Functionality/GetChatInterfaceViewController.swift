import UIKit
protocol CustomerDeleteDelegate: AnyObject {
    func didDeleteCustomer(_ customer: Customer)
    func didUpdateCustomer(_ customer: Customer)
}
class GetChatInterfaceViewController: UIViewController {
    var customer: Customer?

    weak var delegate: CustomerDeleteDelegate?
    
    @IBOutlet weak var youReceiveLabel: UILabel!
    @IBOutlet weak var tableView: UITableView!
    
    var transactions: [Payment] = []
    var isNewCustomer: Bool = false
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = customer?.name
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
        youReceiveLabel.clipsToBounds = true
        loadTransactions()
        updateBalance()
    }
    
    private func loadTransactions() {
        guard let customerID = customer?.id else { return }
        // Load real transactions from CreditStore, reversed so newest is at index 0
        transactions = CreditStore.shared.getPayments(forCustomer: customerID).reversed()
        tableView.reloadData()
    }
    
    private func updateBalance() {
        guard let customerID = customer?.id else { return }
        let balance = CreditStore.shared.getNetBalance(forCustomer: customerID)
        
        if balance >= 0 {
            youReceiveLabel.text = "You'll receive ₹\(Int(balance))"
            youReceiveLabel.textColor = UIColor(named: "Lime Moss")!
        } else {
            youReceiveLabel.text = "You owe ₹\(Int(-balance))"
            youReceiveLabel.textColor = .systemRed
        }
        
        // Update the customer's balance and notify parent
        customer?.netBalance = balance
        if let customer = customer {
            delegate?.didUpdateCustomer(customer)
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

        vc.name = customer?.name
        vc.phone = customer?.phone
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
        guard let customer = customer else { return }
            
        let alert = UIAlertController(
            title: "Delete Contact",
            message: "Are you sure you want to delete this contact? All transaction history will be lost.",
            preferredStyle: .alert
        )
            
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            self.delegate?.didDeleteCustomer(customer)
            self.navigationController?.popViewController(animated: true)
        })
            
        present(alert, animated: true)
    }
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "AddGetTransactionSegue" {
            if let addVC = segue.destination as? AddTransactionViewController {
                addVC.customerID = customer?.id
                addVC.delegate = self
            }
        }
    }
}

extension GetChatInterfaceViewController: UITableViewDataSource, UITableViewDelegate {
    
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
            cell.amountLabel.textColor = UIColor(named: "Lime Moss")!
            cell.dateLabel.text = "Received on \(formattedDate)"
            
            // Check for linked bill in note
            if let note = transaction.note, note.localizedCaseInsensitiveContains("Credit sale") {
                let cleanedInvoice = note.replacingOccurrences(of: "Credit sale", with: "", options: .caseInsensitive)
                                         .replacingOccurrences(of: ":", with: "")
                                         .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !cleanedInvoice.isEmpty {
                    cell.chevronButton.isHidden = false
                    cell.tapAction = { [weak self] in
                        self?.showBill(for: cleanedInvoice)
                    }
                } else {
                    cell.chevronButton.isHidden = true
                    cell.tapAction = nil
                }
            } else {
                cell.chevronButton.isHidden = true
                cell.tapAction = nil
            }
            return cell
            
        } else {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: "PaidTableViewCell",
                for: indexPath
            ) as! PaidTableViewCell
            cell.contentView.transform = CGAffineTransform(scaleX: 1, y: -1)
            cell.amountLabel.text = "₹\(Int(transaction.amount))"
            cell.amountLabel.textColor = .systemRed
            cell.dateLabel.text = "Sold on \(formattedDate)"
            
            // Check for linked bill in note
            if let note = transaction.note, note.localizedCaseInsensitiveContains("Credit sale") {
                let cleanedInvoice = note.replacingOccurrences(of: "Credit sale", with: "", options: .caseInsensitive)
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
        
        // Find the original SALE transaction for this invoice
        let allTx = (try? dm.db.getTransactions()) ?? []
        guard let transaction = allTx.first(where: { 
            $0.type == TransactionType.sale && $0.invoiceNumber.lowercased().contains(target) 
        }) else { return }
        
        presentBillSheet(for: transaction)
    }


}

extension GetChatInterfaceViewController: AddTransactionDelegate {
    func didAddTransaction(_ transaction: Payment) {
        // Save to CreditStore
        CreditStore.shared.addPayment(transaction)
        
        // Reload from store
        loadTransactions()
        updateBalance()
        scrollToBottom()
    }
}

extension GetChatInterfaceViewController: EditProfileDelegate {
    func didUpdateProfile(name: String?, phone: String?, image: UIImage?) {
        customer?.name = name ?? "Unknown"
        customer?.phone = phone
        customer?.profileImage = image
        
        if let customer = customer {
            CreditStore.shared.updateCustomer(customer)
            delegate?.didUpdateCustomer(customer)
        }
        
        title = name
    }
}
