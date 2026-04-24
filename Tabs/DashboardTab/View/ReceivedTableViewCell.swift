import UIKit

class ReceivedTableViewCell: UITableViewCell {

    @IBOutlet weak var amountLabel: UILabel!
    @IBOutlet weak var dateLabel: UILabel!
    @IBOutlet weak var chevronButton: UIButton!
    
    var tapAction: (() -> Void)?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        self.backgroundColor = .clear
        contentView.backgroundColor = .clear
        
        chevronButton.isHidden = true // Default hidden
        chevronButton.tintColor = .systemGray
        amountLabel.textColor = UIColor(named: "Lime Moss")
    }
    
    @IBAction func chevronTapped(_ sender: UIButton) {
        tapAction?()
    }
}
