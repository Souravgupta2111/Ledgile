
import UIKit
import Foundation

class TopTileTableViewCell: UITableViewCell {
    protocol TopTileTableViewCellDelegate: AnyObject {
        func topTileCellDidTapInvestment(_ cell: TopTileTableViewCell)
        func topTileCellDidTapPurchase(_ cell: TopTileTableViewCell)
        func topTileCellDidTapLowStock(_ cell: TopTileTableViewCell)
        func topTileCellDidTapExpiring(_ cell: TopTileTableViewCell)
    }
    weak var delegate: TopTileTableViewCellDelegate?
    
    @IBOutlet weak var investmentContainerView: UIView!
    @IBOutlet var purchaseContainerView: UIView!
    @IBOutlet var itemCountLabel: UILabel!
    @IBOutlet weak var amountLabel: UILabel!
    @IBOutlet var purchaseAmountLabel: UILabel!
    @IBOutlet var purchaseCountLabel: UILabel!
    @IBOutlet var purchaseChevron: UIButton!
    @IBOutlet weak var restockCountLabel: UILabel!
    @IBOutlet var lowStockButton: UIButton!
    
    
    @IBOutlet weak var expiryLabel: UILabel!
    
    @IBOutlet weak var investmentChevron: UIButton!
    @IBOutlet var grossMarginLabel: UILabel!
    @IBOutlet var totalPurchasePercent: UILabel!
    
    @IBAction func purchaseChevronTapped(_ sender: UIButton) {
        delegate?.topTileCellDidTapPurchase(self)
    }
    @IBAction func lowStockChevronTapped(_ sender: UIButton) {
        delegate?.topTileCellDidTapLowStock(self)
    }
    
    @IBAction func investmentChevron(_ sender: UIButton) {
        delegate?.topTileCellDidTapInvestment(self)
    }

    @IBAction func expiringButtonTapped(_ sender: UIButton) {
        delegate?.topTileCellDidTapExpiring(self)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        selectionStyle = .none
    }
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }

    
    func configure(investmentAmount: String, itemCount: String, purchaseAmount: String, purchaseCount: String, lowStockCountText: String, grossMarginPercent: Double? = nil, purchasePercentChange: Double? = nil, expiryText: String) {
                
        amountLabel.text = investmentAmount
        itemCountLabel.text = itemCount
        purchaseAmountLabel.text = purchaseAmount
        purchaseCountLabel.text = purchaseCount
        restockCountLabel.text = lowStockCountText
        expiryLabel.text = expiryText
            
                // Gross Margin
        if let margin = grossMarginPercent {
            grossMarginLabel.text = String(format: "Margin : %.1f%%", margin)
        } else {
            grossMarginLabel.text = "Margin : 0.0%"
        }
        grossMarginLabel.textColor = .white
            
                // Purchase percent change from yesterday
        applyPurchasePercentChange(label: totalPurchasePercent, value: purchasePercentChange)
    }
        
        private func applyPurchasePercentChange(label: UILabel, value: Double?) {
            guard let value = value else {
                label.text = "0.0%"
                label.textColor = .secondaryLabel
                return
            }
            
            let absValue = abs(value)
            if value > 0 {
                label.text = String(format: "+ %.1f%%", absValue)
                label.textColor = UIColor(named: "Lime Moss")!
            } else if value < 0 {
                label.text = String(format: "- %.1f%%", absValue)
                label.textColor = .systemRed
            } else {
                label.text = "0.0%"
                label.textColor = .black
            }
        }
}

