import UIKit
protocol AddPayTransactionDelegate: AnyObject {
    func didAddTransaction(_ transaction: SupplierPayment)
}
class PayAddTransactionViewController: UIViewController {
    weak var delegate: AddPayTransactionDelegate?
    var supplierID: UUID?

    @IBOutlet weak var segment: UISegmentedControl!
    @IBOutlet weak var textField: UITextField!
    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var noteLabel: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        textField.placeholder = "0.00"
        noteLabel.placeholder = "What's this payment for?"
        
        textField.layer.cornerRadius = 20
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UIColor.systemGray4.cgColor
        
        noteLabel.layer.cornerRadius = 20
        noteLabel.layer.borderWidth = 1
        noteLabel.layer.borderColor = UIColor.systemGray4.cgColor
        updateDetails()
    }

    func updateDetails() {
        if segment.selectedSegmentIndex == 0 {
            label.text = "- ₹"
            label.textColor = .systemRed
        } else if segment.selectedSegmentIndex == 1 {
            label.text = "+ ₹"
            label.textColor = UIColor(named: "Lime Moss")!
        }
    }
    
    @IBAction func segmentChanged(_ sender: UISegmentedControl) {
        updateDetails()
    }
    
    @IBAction func saveButtonTapped(_ sender: UIBarButtonItem) {
        guard let amountText = textField.text, let amount = Double(amountText), amount > 0 else { return }
        guard let supplierID = supplierID else { return }
                
        let type: CreditTransactionType = segment.selectedSegmentIndex == 0 ? .received : .paid
        let note = noteLabel.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                
        let transaction = SupplierPayment(
            id: UUID(),
            supplierID: supplierID,
            amount: amount,
            date: Date(),
            type: type,
            note: note?.isEmpty == true ? nil : note
        )
                
        delegate?.didAddTransaction(transaction)
        navigationController?.popViewController(animated: true)
        dismiss(animated: true)
    }
    
}

