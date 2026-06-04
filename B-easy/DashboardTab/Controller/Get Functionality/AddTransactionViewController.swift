import UIKit
protocol AddTransactionDelegate: AnyObject {
    func didAddTransaction(_ transaction: Payment)
}
class AddTransactionViewController: UIViewController {
    weak var delegate: AddTransactionDelegate?
    var customerID: UUID?

    @IBOutlet weak var textField: UITextField!
    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var noteLabel: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "You Received"
        textField.placeholder = "0.00"
        noteLabel.placeholder = "What's this payment for?"
        
        textField.layer.cornerRadius = 20
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UIColor.systemGray4.cgColor
        
        noteLabel.layer.cornerRadius = 20
        noteLabel.layer.borderWidth = 1
        noteLabel.layer.borderColor = UIColor.systemGray4.cgColor

        // Always "You Received" → + ₹
        label.text = "+ ₹"
        label.textColor = UIColor(named: "Lime Moss")!
    }
    
    @IBAction func saveButtonTapped(_ sender: UIBarButtonItem) {
        guard let amountText = textField.text, let amount = Double(amountText), amount > 0 else { return }
        guard let customerID = customerID else { return }
                
        let note = noteLabel.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                
        let transaction = Payment(
            id: UUID(),
            customerID: customerID,
            amount: amount,
            date: Date(),
            type: .received,
            note: note?.isEmpty == true ? nil : note
        )
                
        delegate?.didAddTransaction(transaction)
        navigationController?.popViewController(animated: true)
        dismiss(animated: true)
    }
    
}
