
import UIKit

class SalesItemTableViewCell: UITableViewCell {

    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var detailLabel: UILabel!
    @IBOutlet var priceLabel: UILabel!

    let chevronImageView = UIImageView()
    let card = UIView()
    private let bottomSeparator = UIView()
    private var cardBottomConstraint: NSLayoutConstraint?
    private var didSetupUI = false

    override func awakeFromNib() {
        super.awakeFromNib()
        setupUI()
    }

    private func setupUI() {
        guard !didSetupUI else { return }
        didSetupUI = true

        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        contentView.subviews.forEach { $0.removeFromSuperview() }
        [titleLabel, detailLabel, priceLabel].forEach {
            $0?.removeConstraints($0?.constraints ?? [])
        }

        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.layer.masksToBounds = true
        contentView.addSubview(card)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 1

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabel
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.numberOfLines = 1

        priceLabel.translatesAutoresizingMaskIntoConstraints = false
        priceLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        priceLabel.textColor = .label
        priceLabel.textAlignment = .right
        priceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        priceLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        chevronImageView.translatesAutoresizingMaskIntoConstraints = false
        chevronImageView.contentMode = .scaleAspectFit
        chevronImageView.tintColor = .tertiaryLabel
        let chevronConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        chevronImageView.image = UIImage(systemName: "chevron.down", withConfiguration: chevronConfig)

        bottomSeparator.translatesAutoresizingMaskIntoConstraints = false
        bottomSeparator.backgroundColor = .separator
        bottomSeparator.isHidden = true

        card.addSubview(titleLabel)
        card.addSubview(detailLabel)
        card.addSubview(priceLabel)
        card.addSubview(chevronImageView)
        card.addSubview(bottomSeparator)

        let bottomConstraint = card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4)
        cardBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bottomConstraint,

            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: priceLabel.leadingAnchor, constant: -12),

            detailLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: priceLabel.leadingAnchor, constant: -12),
            detailLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),

            chevronImageView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            chevronImageView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: 14),
            chevronImageView.heightAnchor.constraint(equalToConstant: 14),

            priceLabel.trailingAnchor.constraint(equalTo: chevronImageView.leadingAnchor, constant: -8),
            priceLabel.centerYAnchor.constraint(equalTo: card.centerYAnchor),

            bottomSeparator.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            bottomSeparator.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            bottomSeparator.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            bottomSeparator.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }

    func configureExpansion(isExpanded: Bool) {
        setupUI()
        let chevronConfig = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        chevronImageView.image = UIImage(systemName: isExpanded ? "chevron.up" : "chevron.down", withConfiguration: chevronConfig)

        if isExpanded {
            cardBottomConstraint?.constant = 0
            card.layer.cornerRadius = 14
            card.layer.cornerCurve = .continuous
            card.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            bottomSeparator.isHidden = false
        } else {
            cardBottomConstraint?.constant = -4
            card.layer.cornerRadius = 14
            card.layer.cornerCurve = .continuous
            card.layer.maskedCorners = [
                .layerMinXMinYCorner,
                .layerMaxXMinYCorner,
                .layerMinXMaxYCorner,
                .layerMaxXMaxYCorner
            ]
            bottomSeparator.isHidden = true
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        accessoryView = nil
        accessoryType = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
}
