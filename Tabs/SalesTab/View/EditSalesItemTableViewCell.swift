
import UIKit

class EditSalesItemTableViewCell: UITableViewCell {

    @IBOutlet var nameLabel: UITextField!
    @IBOutlet var stepper: UIStepper!
    @IBOutlet var quantityLabel: UILabel!
    @IBOutlet var unitLabel: UITextField!
    @IBOutlet var priceLabel: UITextField!
    @IBOutlet var deleteButton: UIButton!
    
    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
    
}
