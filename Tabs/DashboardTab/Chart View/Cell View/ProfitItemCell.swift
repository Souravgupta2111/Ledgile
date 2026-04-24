import UIKit

final class ProfitItemCell: UITableViewCell {

    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var quantityLabel: UILabel!
    @IBOutlet weak var costLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()
        
        backgroundColor = .systemBackground
        contentView.backgroundColor = .systemBackground
        
        selectionStyle = .none
    }

    func configure(with item: Item, quantitySold: Int) {
        nameLabel.text = item.name

        let costPerUnit = item.defaultCostPrice
        let sellingPerUnit = item.defaultSellingPrice

        quantityLabel.text = "Sold: \(quantitySold) | Cost Price: ₹\(Int(costPerUnit))/pc"

        let profitPerUnit = sellingPerUnit - costPerUnit
        let totalProfit = profitPerUnit * Double(quantitySold)

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0

        let formattedProfit = formatter.string(from: NSNumber(value: totalProfit)) ?? "0"

        costLabel.text = "₹\(formattedProfit)"
        costLabel.textColor = totalProfit >= 0 ? UIColor(named: "Lime Moss")! : .systemRed
    }
}
