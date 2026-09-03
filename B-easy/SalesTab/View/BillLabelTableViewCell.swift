//
//  BillLabelTableViewCell.swift
//  Tabs
//
//  Created by GEU  on 19/03/26.
//

import UIKit

class BillLabelTableViewCell: UITableViewCell {
    
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var dateLabel: UILabel!
    override func awakeFromNib() {
        super.awakeFromNib()
        titleLabel.textColor = .label
        dateLabel.textColor = .secondaryLabel
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

    }
    
}
