import UIKit
protocol AddPayTransactionDelegate: AnyObject {
    func didAddTransaction(_ transaction: SupplierPayment)
}
class PayAddTransactionViewController: UIViewController {
    weak var delegate: AddPayTransactionDelegate?
    var supplierID: UUID?

    @IBOutlet weak var textField: UITextField!
    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var noteLabel: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "You Paid"
        textField.placeholder = "0.00"
        noteLabel.placeholder = "What's this payment for?"
        
        textField.layer.cornerRadius = 20
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UIColor.systemGray4.cgColor
        
        noteLabel.layer.cornerRadius = 20
        noteLabel.layer.borderWidth = 1
        noteLabel.layer.borderColor = UIColor.systemGray4.cgColor

        // Always "You Paid" → - ₹
        label.text = "- ₹"
        label.textColor = .systemRed
    }
    
    @IBAction func saveButtonTapped(_ sender: UIBarButtonItem) {
        guard let amountText = textField.text, let amount = Double(amountText), amount > 0 else { return }
        guard let supplierID = supplierID else { return }
                
        let note = noteLabel.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                
        let transaction = SupplierPayment(
            id: UUID(),
            supplierID: supplierID,
            amount: amount,
            date: Date(),
            type: .paid,
            note: note?.isEmpty == true ? nil : note
        )
                
        delegate?.didAddTransaction(transaction)
        navigationController?.popViewController(animated: true)
        dismiss(animated: true)
    }
    
}
