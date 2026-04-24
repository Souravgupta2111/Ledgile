
import UIKit

class AddNewItemTableViewCell: UITableViewCell {

    @IBOutlet weak var addButton: UIButton!
    
   
    var onAddTapped: (() -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
        addButton.addTarget(self, action: #selector(addTapped), for: UIControl.Event.touchUpInside)
        addButton.tintColor = UIColor(named: "Lime Moss")
    }

    @objc private func addTapped() {
        onAddTapped?()
    }
}
