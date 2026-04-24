import UIKit

class SearchTabTableViewCell: UITableViewCell {
    @IBOutlet weak var searchCategoryLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        backgroundColor = .clear
        contentView.backgroundColor = .secondarySystemGroupedBackground
        searchCategoryLabel.font = .systemFont(ofSize: 15, weight: .regular)
        searchCategoryLabel.textColor = .secondaryLabel
    }
}
