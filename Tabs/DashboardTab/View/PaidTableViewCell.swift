//
//  PaidTableViewCell.swift
//  Credit
//
//  Created by GEU  on 30/03/26.
//

import UIKit

class PaidTableViewCell: UITableViewCell {

    @IBOutlet weak var amountLabel: UILabel!
    @IBOutlet weak var dateLabel: UILabel!
    @IBOutlet weak var chevronButton: UIButton!
    
    var tapAction: (() -> Void)?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        self.backgroundColor = .clear
        contentView.backgroundColor = .clear
        
        chevronButton.isHidden = true // Default hidden, shown only for bills
        chevronButton.tintColor = .systemGray
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
    
    @IBAction func chevronTapped(_ sender: UIButton) {
        tapAction?()
    }
}
