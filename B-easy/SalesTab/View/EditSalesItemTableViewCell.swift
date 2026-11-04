import UIKit

class EditSalesItemTableViewCell: UITableViewCell {

    @IBOutlet var nameLabel: UITextField!
    @IBOutlet weak var quantityLabel: UITextField!
    @IBOutlet var unitLabel: UITextField!
    @IBOutlet var priceLabel: UITextField!
    @IBOutlet var deleteButton: UIButton!

    private var didSetupUI = false

    override func awakeFromNib() {
        super.awakeFromNib()
        setupUI()
    }

    func setupUI() {
        guard !didSetupUI else { return }
        didSetupUI = true

        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        // Discard legacy XIB views from contentView
        contentView.subviews.forEach { $0.removeFromSuperview() }

        // Remove lingering constraints from XIB on outlet subviews
        [nameLabel, quantityLabel, unitLabel, priceLabel, deleteButton].forEach {
            $0?.removeConstraints($0?.constraints ?? [])
        }

        // Outer white card container
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.layer.masksToBounds = true
        contentView.addSubview(card)

        let fieldFill = UIColor.secondarySystemBackground

        // 1. Name field with search icon on the left
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.borderStyle = .none
        nameLabel.backgroundColor = fieldFill
        nameLabel.layer.cornerRadius = 10
        nameLabel.layer.cornerCurve = .continuous
        nameLabel.layer.masksToBounds = true
        nameLabel.font = .systemFont(ofSize: 15, weight: .regular)
        nameLabel.textColor = .label
        nameLabel.placeholder = "Item name"
        nameLabel.isUserInteractionEnabled = true

        let searchIcon = UIImageView(image: UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)))
        searchIcon.tintColor = .secondaryLabel
        searchIcon.contentMode = .scaleAspectFit
        searchIcon.isUserInteractionEnabled = false
        let searchContainer = UIView(frame: CGRect(x: 0, y: 0, width: 34, height: 40))
        searchContainer.isUserInteractionEnabled = false
        searchIcon.frame = CGRect(x: 10, y: 12, width: 16, height: 16)
        searchContainer.addSubview(searchIcon)
        nameLabel.leftView = searchContainer
        nameLabel.leftViewMode = .always

        // 2. Delete trash button
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        let trashConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        deleteButton.setImage(UIImage(systemName: "trash", withConfiguration: trashConfig), for: .normal)
        deleteButton.tintColor = .systemRed
        deleteButton.backgroundColor = .clear

        let topRow = UIStackView(arrangedSubviews: [nameLabel, deleteButton])
        topRow.translatesAutoresizingMaskIntoConstraints = false
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 10
        card.addSubview(topRow)

        // 3. Quantity field
        quantityLabel.translatesAutoresizingMaskIntoConstraints = false
        quantityLabel.borderStyle = .none
        quantityLabel.backgroundColor = fieldFill
        quantityLabel.layer.cornerRadius = 10
        quantityLabel.layer.cornerCurve = .continuous
        quantityLabel.layer.masksToBounds = true
        quantityLabel.font = .systemFont(ofSize: 14, weight: .regular)
        quantityLabel.textColor = .label
        quantityLabel.placeholder = "Qty"
        quantityLabel.isUserInteractionEnabled = true
        let qtyPadding = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 38))
        qtyPadding.isUserInteractionEnabled = false
        quantityLabel.leftView = qtyPadding
        quantityLabel.leftViewMode = .always

        // 4. Unit field with downward chevron
        unitLabel.translatesAutoresizingMaskIntoConstraints = false
        unitLabel.borderStyle = .none
        unitLabel.backgroundColor = fieldFill
        unitLabel.layer.cornerRadius = 10
        unitLabel.layer.cornerCurve = .continuous
        unitLabel.layer.masksToBounds = true
        unitLabel.font = .systemFont(ofSize: 14, weight: .regular)
        unitLabel.textColor = .label
        unitLabel.placeholder = "Unit"
        unitLabel.isUserInteractionEnabled = true
        unitLabel.inputView = UIView()
        let unitPadding = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 38))
        unitPadding.isUserInteractionEnabled = false
        unitLabel.leftView = unitPadding
        unitLabel.leftViewMode = .always

        let chevron = UIImageView(image: UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)))
        chevron.tintColor = .secondaryLabel
        chevron.contentMode = .scaleAspectFit
        chevron.isUserInteractionEnabled = false
        let chevronContainer = UIView(frame: CGRect(x: 0, y: 0, width: 22, height: 38))
        chevronContainer.isUserInteractionEnabled = false
        chevron.frame = CGRect(x: 2, y: 14, width: 10, height: 10)
        chevronContainer.addSubview(chevron)
        unitLabel.rightView = chevronContainer
        unitLabel.rightViewMode = .always

        // 5. Price field
        priceLabel.translatesAutoresizingMaskIntoConstraints = false
        priceLabel.borderStyle = .none
        priceLabel.backgroundColor = fieldFill
        priceLabel.layer.cornerRadius = 10
        priceLabel.layer.cornerCurve = .continuous
        priceLabel.layer.masksToBounds = true
        priceLabel.font = .systemFont(ofSize: 14, weight: .regular)
        priceLabel.textColor = .label
        priceLabel.placeholder = "Price (₹)"
        priceLabel.isUserInteractionEnabled = true
        let pricePadding = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 38))
        pricePadding.isUserInteractionEnabled = false
        priceLabel.leftView = pricePadding
        priceLabel.leftViewMode = .always

        let bottomRow = UIStackView(arrangedSubviews: [quantityLabel, unitLabel, priceLabel])
        bottomRow.translatesAutoresizingMaskIntoConstraints = false
        bottomRow.axis = .horizontal
        bottomRow.alignment = .fill
        bottomRow.distribution = .fill
        bottomRow.spacing = 8
        card.addSubview(bottomRow)

        NSLayoutConstraint.activate([
            // Card constraints inside cell
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            // Top row
            topRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            topRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            topRow.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),

            nameLabel.heightAnchor.constraint(equalToConstant: 40),
            deleteButton.widthAnchor.constraint(equalToConstant: 30),
            deleteButton.heightAnchor.constraint(equalToConstant: 40),

            // Bottom row
            bottomRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            bottomRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            bottomRow.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 10),
            bottomRow.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            bottomRow.heightAnchor.constraint(equalToConstant: 38),

            // Proportions: Qty ~24%, Unit ~28%, Price takes remaining ~48%
            quantityLabel.widthAnchor.constraint(equalTo: bottomRow.widthAnchor, multiplier: 0.24),
            unitLabel.widthAnchor.constraint(equalTo: bottomRow.widthAnchor, multiplier: 0.28)
        ])
    }
}
