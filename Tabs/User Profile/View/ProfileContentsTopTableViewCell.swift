import UIKit

final class ProfileContentsTopTableViewCell: UITableViewCell {

    @IBOutlet private weak var profileImageView: UIImageView!
    @IBOutlet private weak var nameLabel: UILabel!
    @IBOutlet private weak var phoneLabel: UILabel!
    @IBOutlet private weak var editButton: UIButton!

    var onEditProfileTapped: (() -> Void)?
    var onImageTapped: (() -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
        selectionStyle = .none

        profileImageView.clipsToBounds = true
        profileImageView.isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleImageTap))
        profileImageView.addGestureRecognizer(tap)

        styleEditButton()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onEditProfileTapped = nil
        onImageTapped = nil
    }

    func configure(name: String, phone: String?, image: UIImage?) {
        nameLabel.text = name
        phoneLabel.text = (phone?.isEmpty == false ? phone : "No phone number")

        nameLabel.font = .systemFont(ofSize: 24, weight: .bold)
        nameLabel.textColor = .white

        phoneLabel.font = .systemFont(ofSize: 15, weight: .medium)
        phoneLabel.textColor = .white.withAlphaComponent(0.95)

        if let image {
            profileImageView.image = image
            profileImageView.contentMode = .scaleAspectFill
            profileImageView.tintColor = nil
            profileImageView.backgroundColor = .clear
        } else {
            profileImageView.image = UIImage(systemName: "person.fill")
            profileImageView.contentMode = .scaleAspectFit
            profileImageView.tintColor = .tertiaryLabel
            profileImageView.backgroundColor = .tertiarySystemGroupedBackground
        }
    }

    @IBAction private func editImageTapped(_ sender: UIButton) {
        // XIB action is currently wired to this selector. Keep name, route to profile editing only.
        onEditProfileTapped?()
    }

    @objc private func handleImageTap() {
        onImageTapped?()
    }

    private func styleEditButton() {
        var configuration = editButton.configuration ?? UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        editButton.configuration = configuration
        editButton.setTitleColor(.white, for: .normal)
        editButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        editButton.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        editButton.layer.cornerRadius = 16
        editButton.clipsToBounds = true
    }
}
