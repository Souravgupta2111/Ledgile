import UIKit

class LabelTableViewCell: UITableViewCell {

    @IBOutlet weak var containerView: UIView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var separatorView: UIView!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        backgroundColor = .clear
        contentView.backgroundColor = .systemGray6
        
        containerView.backgroundColor = .systemBackground
        containerView.layer.masksToBounds = true
        containerView.layer.cornerCurve = .continuous
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        let color = selected ? UIColor.systemGray5 : UIColor.systemBackground

        if animated {
            UIView.animate(withDuration: 0.25) {
                self.containerView.backgroundColor = color
            }
        } else {
            containerView.backgroundColor = color
        }
    }
    
    func applyCornerMask(isFirst: Bool, isLast: Bool) {
        
        containerView.layer.cornerRadius = 30
        separatorView.isHidden = false

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
            separatorView.isHidden = true
        } else {
            containerView.layer.maskedCorners = []
        }
    }
}
