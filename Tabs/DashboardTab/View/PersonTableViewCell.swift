import UIKit

class PersonTableViewCell: UITableViewCell {
    
    @IBOutlet weak var profileImageView: UIImageView!
    @IBOutlet weak var initialLabel: UILabel!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var priceLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        profileImageView.clipsToBounds = true
    }
    
    func configureProfile(name: String, image: UIImage?) {
        if let img = image {
            profileImageView.image = img
            profileImageView.isHidden = false
            initialLabel.isHidden = true
        } else {
            profileImageView.isHidden = true
            initialLabel.isHidden = false

            let firstLetter = String(name.prefix(1)).uppercased()
            initialLabel.text = firstLetter
            initialLabel.clipsToBounds = true
        }
    }

    func configureMenuRow(title: String, detail: String? = nil, icon: UIImage?, detailColor: UIColor = .secondaryLabel) {
        nameLabel.text = title
        nameLabel.textColor = .label

        priceLabel.text = detail
        priceLabel.textColor = detailColor
        priceLabel.font = .systemFont(ofSize: 15, weight: .regular)

        initialLabel.isHidden = true
        profileImageView.isHidden = false
        profileImageView.image = icon
        profileImageView.tintColor = .systemGray
        profileImageView.contentMode = .scaleAspectFit
    }
}
