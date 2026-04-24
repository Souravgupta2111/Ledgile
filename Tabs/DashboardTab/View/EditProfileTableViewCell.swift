import UIKit

class EditProfileTableViewCell: UITableViewCell {

    @IBOutlet weak var textField: UITextField!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        textField.layer.cornerRadius = 12
        textField.layer.masksToBounds = true
            
        textField.backgroundColor = UIColor(named: "CellColor")
        textField.borderStyle = .none
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UIColor.systemGray4.cgColor
        textField.addPadding(left: 12, right: 12)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
    
}
extension UITextField {
    func addPadding(left: CGFloat = 12, right: CGFloat = 12) {
        let leftView = UIView(frame: CGRect(x: 0, y: 0, width: left, height: 0))
        leftViewMode = .always
        self.leftView = leftView
        
        let rightView = UIView(frame: CGRect(x: 0, y: 0, width: right, height: 0))
        rightViewMode = .always
        self.rightView = rightView
    }
}
