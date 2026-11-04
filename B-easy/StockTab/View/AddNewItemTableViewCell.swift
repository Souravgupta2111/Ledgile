import UIKit

class AddNewItemTableViewCell: UITableViewCell {

    @IBOutlet weak var addButton: UIButton!
    var onAddTapped: (() -> Void)?
    private var didSetupUI = false

    override func awakeFromNib() {
        super.awakeFromNib()
        setupUI()
    }

    func setupUI() {
        guard !didSetupUI else { return }
        didSetupUI = true

        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        contentView.subviews.forEach { $0.removeFromSuperview() }

        let lime = UIColor(named: "Lime Moss") ?? .systemGreen
        addButton?.removeFromSuperview()
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.backgroundColor = lime.withAlphaComponent(0.12)
        addButton.layer.cornerRadius = 12
        addButton.layer.cornerCurve = .continuous
        addButton.layer.masksToBounds = true
        addButton.tintColor = lime
        addButton.setTitleColor(lime, for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        let plusConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        addButton.setImage(UIImage(systemName: "plus.circle", withConfiguration: plusConfig), for: .normal)
        addButton.setTitle("  Add another item", for: .normal)
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        contentView.addSubview(addButton)

        NSLayoutConstraint.activate([
            addButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            addButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            addButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            addButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            addButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }

    @objc private func addTapped() {
        onAddTapped?()
    }
}
