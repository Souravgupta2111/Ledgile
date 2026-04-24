import UIKit

enum ProfileCellAccessoryStyle {
    case chevron
    case toggle(isOn: Bool)
    case none
}

final class ProfileContentsTableViewCell: UITableViewCell {

    @IBOutlet private weak var iconImageView: UIImageView!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var chevronButton: UIButton!
    @IBOutlet private weak var toggleSwitch: UISwitch!

    var onToggleChanged: ((Bool) -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
        toggleSwitch.addTarget(self, action: #selector(toggleValueChanged(_:)), for: .valueChanged)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onToggleChanged = nil
        titleLabel.textColor = .label
        iconImageView.tintColor = .label
        chevronButton.isHidden = true
        toggleSwitch.isHidden = true
    }

    func configure(
        icon: UIImage? = nil,
        title: String,
        accessoryStyle: ProfileCellAccessoryStyle = .chevron,
        titleColor: UIColor = .label
    ) {
        iconImageView.image = icon
        iconImageView.tintColor = titleColor
        iconImageView.isHidden = (icon == nil)

        titleLabel.attributedText = nil
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 17, weight: .regular)
        titleLabel.textColor = titleColor
        titleLabel.numberOfLines = 1

        switch accessoryStyle {
        case .chevron:
            chevronButton.isHidden = false
            toggleSwitch.isHidden = true
            selectionStyle = .default

        case .toggle(let isOn):
            chevronButton.isHidden = true
            toggleSwitch.isHidden = false
            toggleSwitch.isOn = isOn
            selectionStyle = .none

        case .none:
            chevronButton.isHidden = true
            toggleSwitch.isHidden = true
            selectionStyle = .default
        }
    }

    func configure(title: String, subtitle: String? = nil, showsChevron: Bool = true) {
        configure(
            icon: nil,
            title: title,
            accessoryStyle: showsChevron ? .chevron : .none
        )
    }

    @objc private func toggleValueChanged(_ sender: UISwitch) {
        onToggleChanged?(sender.isOn)
    }
}
