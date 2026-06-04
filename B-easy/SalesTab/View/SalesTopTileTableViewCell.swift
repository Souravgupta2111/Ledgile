
import UIKit

class SalesTopTileTableViewCell: UITableViewCell {
    
    protocol SalesTopTileTableViewCellDelegate: AnyObject {
        func topTileCellDidTapRevenue(_ cell: SalesTopTileTableViewCell)
        func topTileCellDidTapProfit(_ cell: SalesTopTileTableViewCell)
    }
    
    weak var delegate: SalesTopTileTableViewCellDelegate?
    @IBOutlet var revenueAmountLabel: UILabel!
    @IBOutlet var profitAmountLabel: UILabel!
    
    @IBOutlet var revenueReceiptsLabel: UILabel!
    @IBOutlet var profitItemsLabel: UILabel!
    
    @IBOutlet var salesChangeFromYesterday: UILabel!
    @IBOutlet var profitChangeFromYesterday: UILabel!
    
    @IBAction func revenueChevronTapped(_ sender: UIButton) {
        delegate?.topTileCellDidTapRevenue(self)
    }
    
    @IBAction func profitChevronTapped(_ sender: UIButton) {
        delegate?.topTileCellDidTapProfit(self)
    }
    override func awakeFromNib() {
        super.awakeFromNib()
        selectionStyle = .none
        
        revenueAmountLabel.superview?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleRevenueTap)))
        revenueAmountLabel.superview?.isUserInteractionEnabled = true
        
        profitAmountLabel.superview?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleProfitTap)))
        profitAmountLabel.superview?.isUserInteractionEnabled = true
    }

    @objc private func handleRevenueTap() { delegate?.topTileCellDidTapRevenue(self) }
    @objc private func handleProfitTap() { delegate?.topTileCellDidTapProfit(self) }
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
    func configure(revenueAmount: String, profitAmount: String, revenueReceipts: String, profitItems: String, salesPercentChange: Double? = nil, profitPercentChange: Double? = nil) {
            revenueAmountLabel.text = revenueAmount
            profitAmountLabel.text = profitAmount
            revenueReceiptsLabel.text = revenueReceipts
            profitItemsLabel.text = profitItems

        
            applySalesPercentChange(label: salesChangeFromYesterday, value: salesPercentChange)
            applyProfitPercentChange(label: profitChangeFromYesterday, value: profitPercentChange)
        }
        
        private func applySalesPercentChange(label: UILabel, value: Double?) {
            guard let value = value else {
                label.text = "0.0%"
                return
            }
            
            let absValue = abs(value)
            if value > 0 {
                label.text = String(format: "+ %.1f%%", absValue)
            } else if value < 0 {
                label.text = String(format: "- %.1f%%", absValue)
            } else {
                label.text = "0.0%"
            }
        }
        
        private func applyProfitPercentChange(label: UILabel, value: Double?) {
            guard let value = value else {
                label.text = "0.0%"
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
            }
        }
}
