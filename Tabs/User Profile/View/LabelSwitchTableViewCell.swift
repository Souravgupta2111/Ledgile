import UIKit

final class LabelSwitchTableViewCell: UITableViewCell {

    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var switchControl: UISwitch!

    var onToggleChanged: ((Bool) -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
        switchControl.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
        selectionStyle = .none
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onToggleChanged = nil
        titleLabel.text = nil
    }

    func configure(title: String, isOn: Bool, onToggleChanged: @escaping (Bool) -> Void) {
        titleLabel.text = title
        switchControl.isOn = isOn
        self.onToggleChanged = onToggleChanged
    }

    @objc private func toggleChanged(_ sender: UISwitch) {
        onToggleChanged?(sender.isOn)
    }
}
