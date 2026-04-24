import UIKit

class AfterSearchTableViewCell: UITableViewCell {
    @IBOutlet weak var searchedTitle: UILabel!
    @IBOutlet weak var searchedSubTitle: UILabel!

    private var didSetupConstraints = false

    override func awakeFromNib() {
        super.awakeFromNib()
        backgroundColor = .clear
        contentView.backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 30
        layer.masksToBounds = true

        searchedTitle.font = .systemFont(ofSize: 17, weight: .regular)
        searchedSubTitle.font = .systemFont(ofSize: 14, weight: .regular)
        searchedSubTitle.textColor = .secondaryLabel
        searchedSubTitle.numberOfLines = 0

        installLabelConstraintsIfNeeded()
    }

    private func installLabelConstraintsIfNeeded() {
        guard !didSetupConstraints else { return }
        didSetupConstraints = true

        searchedTitle.translatesAutoresizingMaskIntoConstraints = false
        searchedSubTitle.translatesAutoresizingMaskIntoConstraints = false

        let bottomConstraint = searchedSubTitle.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)
        bottomConstraint.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            searchedTitle.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            searchedTitle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            searchedTitle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            searchedSubTitle.topAnchor.constraint(equalTo: searchedTitle.bottomAnchor, constant: 6),
            searchedSubTitle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            searchedSubTitle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            bottomConstraint
        ])
    }
}
