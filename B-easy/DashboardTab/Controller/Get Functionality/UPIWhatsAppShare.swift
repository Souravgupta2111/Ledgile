import UIKit
import CoreImage

enum UPIWhatsAppShare {
    static func indianMobileDigits(_ raw: String?) -> String? {
        let digits = (raw ?? "").filter(\.isNumber)
        if digits.count == 12, digits.hasPrefix("91") {
            return String(digits.suffix(10))
        }
        if digits.count == 10 {
            return digits
        }
        return nil
    }

    static func cleanedVPA(_ settings: AppSettings) -> String? {
        let vpa = settings.upiVPA?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return vpa.isEmpty ? nil : vpa
    }

    static func canCollect(with settings: AppSettings?) -> Bool {
        guard let settings else { return false }
        let hasQR = settings.upiQRImageData != nil && !(settings.upiQRImageData?.isEmpty ?? true)
        return cleanedVPA(settings) != nil || hasQR
    }

    /// NPCI UPI pay intent. `am` prefills amount; `mam=null` asks the PSP not to leave it editable.
    static func payIntentURL(vpa: String, payeeName: String, amount: Double, note: String) -> String {
        var components = URLComponents()
        components.scheme = "upi"
        components.host = "pay"
        components.queryItems = [
            URLQueryItem(name: "pa", value: vpa),
            URLQueryItem(name: "pn", value: payeeName),
            URLQueryItem(name: "am", value: String(format: "%.2f", Money.round2(amount))),
            URLQueryItem(name: "mam", value: "null"),
            URLQueryItem(name: "cu", value: "INR"),
            URLQueryItem(name: "tn", value: note)
        ]
        return components.string ?? "upi://pay"
    }

    static func amountQRImage(from intent: String) -> UIImage? {
        guard let data = intent.data(using: .isoLatin1) else { return nil }
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(data, forKey: "inputMessage")
        filter?.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter?.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    static func paymentMessage(
        amount: Double,
        shopName: String,
        settings: AppSettings
    ) -> String {
        let rupees = String(format: "₹%.0f", amount)
        var lines: [String] = [
            "Namaste,",
            "Please pay \(rupees) to \(shopName)."
        ]
        if let vpa = cleanedVPA(settings) {
            let intent = payIntentURL(
                vpa: vpa,
                payeeName: shopName,
                amount: amount,
                note: "\(shopName) \(rupees)"
            )
            lines.append("Tap this link — \(rupees) is already filled. Confirm with your UPI PIN:")
            lines.append(intent)
            lines.append("Or scan the QR in PhonePe, GPay, or Paytm. Same amount.")
        } else {
            lines.append("UPI: scan the shop QR and type \(rupees).")
        }
        lines.append("After you pay, tell the shop. This does not auto-mark paid.")
        return lines.joined(separator: "\n")
    }

    static func presentShare(
        from viewController: UIViewController,
        amount: Double,
        shopName: String,
        settings: AppSettings,
        completion: (() -> Void)? = nil
    ) {
        let text = paymentMessage(amount: amount, shopName: shopName, settings: settings)
        var items: [Any] = [text]
        if let vpa = cleanedVPA(settings) {
            let intent = payIntentURL(
                vpa: vpa,
                payeeName: shopName,
                amount: amount,
                note: "\(shopName) \(String(format: "₹%.0f", amount))"
            )
            if let qr = amountQRImage(from: intent) {
                items.append(qr)
            }
        } else if let data = settings.upiQRImageData, let image = UIImage(data: data) {
            items.append(image)
        }

        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activity.completionWithItemsHandler = { _, _, _, _ in
            completion?()
        }
        if let popover = activity.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        viewController.present(activity, animated: true)
    }

    static func offerAfterCreditSale(
        from viewController: UIViewController,
        amount: Double,
        customerPhone: String?,
        completion: @escaping () -> Void
    ) {
        let settings = try? AppDataModel.shared.dataModel.db.getSettings()
        guard canCollect(with: settings), let settings else {
            completion()
            return
        }
        guard indianMobileDigits(customerPhone) != nil else {
            completion()
            return
        }

        let shop = settings.businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        let shopName = shop.isEmpty ? "the shop" : shop
        let rupees = String(format: "₹%.0f", amount)
        let fillsAmount = cleanedVPA(settings) != nil

        let alert = UIAlertController(
            title: "Send on WhatsApp?",
            message: fillsAmount
                ? "They get a link and QR with \(rupees) already filled. They still enter UPI PIN. You still tap You Received."
                : "Add your UPI ID in Account so the amount is filled automatically. Sharing shop QR only for now.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Send", style: .default) { _ in
            presentShare(
                from: viewController,
                amount: amount,
                shopName: shopName,
                settings: settings,
                completion: completion
            )
        })
        alert.addAction(UIAlertAction(title: "Skip", style: .cancel) { _ in
            completion()
        })
        viewController.present(alert, animated: true)
    }

    static func remindOutstanding(from viewController: UIViewController, customer: Customer) {
        let settings = try? AppDataModel.shared.dataModel.db.getSettings()
        guard canCollect(with: settings), let settings else {
            let alert = UIAlertController(
                title: "Add your UPI ID",
                message: "Open Account → UPI collection and paste your PhonePe, Paytm, or GPay UPI ID. That is what fills the amount on the payment screen.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            viewController.present(alert, animated: true)
            return
        }

        guard indianMobileDigits(customer.phone) != nil else {
            let alert = UIAlertController(
                title: "Mobile required",
                message: "Edit this customer and add a 10-digit mobile number for WhatsApp.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            viewController.present(alert, animated: true)
            return
        }

        let balance = CreditStore.shared.getNetBalance(forCustomer: customer.id)
        guard balance > 0 else {
            let alert = UIAlertController(
                title: "Nothing pending",
                message: "This customer does not owe you right now.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            viewController.present(alert, animated: true)
            return
        }

        let shop = settings.businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        let shopName = shop.isEmpty ? "the shop" : shop
        presentShare(
            from: viewController,
            amount: balance,
            shopName: shopName,
            settings: settings
        )
    }
}
