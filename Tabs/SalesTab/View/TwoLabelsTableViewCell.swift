//
//  TwoLabelsTableViewCell.swift
//  Tabs
//
//  Created by GEU  on 19/03/26.
//

import UIKit

class TwoLabelsTableViewCell: UITableViewCell {
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var detailLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        let onyx = UIColor(named: "Onyx") ?? .black
        titleLabel.textColor = onyx
        detailLabel?.textColor = onyx
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
}
