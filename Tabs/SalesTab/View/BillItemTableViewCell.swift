//
//  BillItemTableViewCell.swift
//  Tabs
//
//  Created by GEU  on 19/03/26.
//

import UIKit

class BillItemTableViewCell: UITableViewCell {

    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var priceLabel: UILabel!
    @IBOutlet var detailLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        let onyx = UIColor(named: "Onyx") ?? .black
        titleLabel.textColor = onyx
        priceLabel.textColor = onyx
        detailLabel.textColor = onyx.withAlphaComponent(0.6)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

    }
    
}
