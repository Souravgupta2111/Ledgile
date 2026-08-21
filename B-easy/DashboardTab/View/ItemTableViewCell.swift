
import UIKit

class ItemTableViewCell: UITableViewCell {

    @IBOutlet weak var symbolView: UIImageView!
    @IBOutlet weak var priceLabel: UILabel!
    @IBOutlet weak var quantityLabel: UILabel!
    @IBOutlet weak var itemNameLabel: UILabel!
    @IBOutlet weak var separatorView: UIView!
    @IBOutlet var containerView: UIView!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        contentView.backgroundColor = .systemGray6
        separatorView.backgroundColor = .separator
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

    }
    func configure(itemName: String, qty: String, price: String, isService: Bool = false) {
        itemNameLabel.text = itemName
        priceLabel.text = price
        if isService {
            quantityLabel.text = "Service"
            quantityLabel.textColor = UIColor(named: "Lime Moss") ?? .systemGreen
        } else {
            quantityLabel.text = "Qty: \(qty)"
            quantityLabel.textColor = .secondaryLabel
        }
    }
    func applySectionCornerMask(isFirst: Bool, isLast: Bool) {
        
        containerView.layer.cornerRadius = 26
        containerView.layer.masksToBounds = true

        containerView.layer.maskedCorners = []

        if isFirst && isLast {
            containerView.layer.maskedCorners = [
                .layerMinXMinYCorner,
                .layerMaxXMinYCorner,
                .layerMinXMaxYCorner,
                .layerMaxXMaxYCorner
            ]
        } else if isFirst {
            containerView.layer.maskedCorners = [
                .layerMinXMinYCorner,
                .layerMaxXMinYCorner
            ]
        } else if isLast {
            containerView.layer.maskedCorners = [
                .layerMinXMaxYCorner,
                .layerMaxXMaxYCorner
            ]
        }

        separatorView.isHidden = isLast
    }
}
