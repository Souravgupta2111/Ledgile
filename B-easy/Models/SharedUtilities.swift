//  Shared utility functions extracted from duplicated implementations.

import UIKit
import Accelerate



extension CGRect {
    /// Intersection over Union between two rectangles.
    func iou(with other: CGRect) -> CGFloat {
        let inter = self.intersection(other)
        guard !inter.isNull else { return 0 }
        let interArea = inter.width * inter.height
        let unionArea = self.width * self.height + other.width * other.height - interArea
        return unionArea > 0 ? interArea / unionArea : 0
    }

    var area: CGFloat { width * height }
}



extension Array where Element == Float {
    func cosineSimilarity(with other: [Float]) -> Float {
        let n = Swift.min(self.count, other.count)
        guard n > 0 else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        vDSP_dotpr(self, 1, other, 1, &dot, vDSP_Length(n))
        vDSP_dotpr(self, 1, self, 1, &normA, vDSP_Length(n))
        vDSP_dotpr(other, 1, other, 1, &normB, vDSP_Length(n))
        let denom = sqrtf(normA) * sqrtf(normB)
        return denom > 0 ? dot / denom : 0
    }
}



extension Double {

    func percentChange(from previous: Double) -> Double {
        if previous != 0 { return ((self - previous) / abs(previous)) * 100 }
        return self > 0 ? 100.0 : 0.0
    }
}

/// Rupees stored and shown to 2 decimals. Quantity (0.23 kg) stays full Double.
enum Money {
    static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    static func line(quantity: Double, rate: Double) -> Double {
        round2(quantity * rate)
    }
}

/// Large-title home tabs (Dashboard / Stock / Sales).
enum HomeTabSpacing {
    static var bottomForFloatingTab: CGFloat { 100 }

    static func apply(to tableView: UITableView) {
        tableView.sectionHeaderTopPadding = 0
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.contentInset.top = 0
        tableView.contentInset.bottom = bottomForFloatingTab
        tableView.verticalScrollIndicatorInsets.bottom = bottomForFloatingTab
    }
}

// MARK: - Bill Presentation

extension UIViewController {
    /// Present a read-only bill sheet for a transaction.
    func presentBillSheet(for transaction: Transaction) {
        let details = transaction.toBillingDetails()
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let billVC: BillTableViewController
        if let storyboardVC = storyboard.instantiateViewController(withIdentifier: "BillTableViewController") as? BillTableViewController {
            billVC = storyboardVC
        } else {
            billVC = BillTableViewController(style: .plain)
        }
        
        billVC.isReadOnly = true
        billVC.receiveBilling(details: details)
        
        let nav = UINavigationController(rootViewController: billVC)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }


    func presentPurchaseScanner() {
        let scanVC = PurchaseScanCameraViewController.instantiate()
        scanVC.onPurchaseResult = { [weak self] result in
            guard let self = self else { return }
            guard let storyboard = self.storyboard,
                  let purchaseVC = storyboard.instantiateViewController(withIdentifier: "AddPurchaseViewController") as? AddPurchaseViewController else { return }
            purchaseVC.pendingPurchaseResult = result
            purchaseVC.entryMode = .camera
            self.navigationController?.pushViewController(purchaseVC, animated: true)
        }
        scanVC.modalPresentationStyle = .fullScreen
        present(scanVC, animated: true)
    }
}

// MARK: - Transaction Cell Configuration

extension ItemTableViewCell {
    func configure(with tx: Transaction) {
        let details = tx.toBillingDetails()

        if tx.type == .sale {
            if let name = tx.customerName, !name.isEmpty {
                itemNameLabel.text = name
            } else {
                itemNameLabel.text = "Cash Sale"
            }
        } else {
            itemNameLabel.text = "Purchase"
        }

        let items = details.items
        if let first = items.first {
            var text = "\(first.itemName) x \(first.quantity)"
            if items.count > 1 {
                text += " + \(items.count - 1) more"
            }
            quantityLabel.text = text
        } else {
            quantityLabel.text = "Unknown"
        }

        priceLabel.textColor = UIColor(named: "Lime Moss")!
        priceLabel.text = "₹\(tx.totalAmount)"
        separatorView.backgroundColor = .separator
    }
}
