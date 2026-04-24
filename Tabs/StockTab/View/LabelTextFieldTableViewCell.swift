
import UIKit

class LabelTextFieldTableViewCell: UITableViewCell {

    @IBOutlet var titleLabel: UILabel!
    
    @IBOutlet var textField: UITextField!
    var onTextChanged: ((String) -> Void)?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        textField.borderStyle = .none
        textField.textAlignment = .right
        textField.font = UIFont.systemFont(ofSize: 17)
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
    }
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.textColor = .label
        textField.rightView = nil
        textField.rightViewMode = .never
        accessoryType = .none
        textField.isUserInteractionEnabled = true
        textField.keyboardType = .default
        onTextChanged = nil
    }

    @objc private func textChanged() {
            onTextChanged?(textField.text ?? "")
        }
}
