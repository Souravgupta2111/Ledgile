import UIKit
import SafariServices

/// Plan picker + Apple IAP checkout. Matches B-easy Lime Moss / Beige / Onyx.
final class ProPlanViewController: UIViewController {

    var isOnboarding = false

    private enum Plan { case yearly, monthly }

    private let lime = UIColor(named: "Lime Moss") ?? .systemGreen
    private let beige = UIColor(named: "Beige") ?? UIColor(red: 0.91, green: 0.90, blue: 0.76, alpha: 1)
    private let onyx = UIColor(named: "Onyx") ?? UIColor(red: 0.05, green: 0.07, blue: 0, alpha: 1)

    private var selected: Plan = .yearly
    private var agreed = false

    private let yearlyCard = UIControl()
    private let monthlyCard = UIControl()
    private let yearlyCheck = UIImageView()
    private let monthlyCheck = UIImageView()
    private let agreeButton = UIButton(type: .system)
    private let payButton = UIButton(type: .system)
    private let yearlyPriceLabel = UILabel()
    private let monthlyPriceLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = beige
        build()
        refreshSelection()
        updatePayTitle()
        Task { @MainActor in
            await ProStore.shared.refresh()
            yearlyPriceLabel.text = "\(ProStore.shared.displayYearlyPrice) per year"
            monthlyPriceLabel.text = "\(ProStore.shared.displayMonthlyPrice) per month"
            updatePayTitle()
        }
    }

    private func build() {
        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Choose a plan\nPlan chunein"
        title.font = .systemFont(ofSize: 32, weight: .bold)
        title.textColor = onyx

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = "You can pay monthly or annually.\nMahine ya saal ka plan le sakte hain."
        subtitle.font = .systemFont(ofSize: 15, weight: .medium)
        subtitle.textColor = UIColor.black.withAlphaComponent(0.45)

        stylePlanCard(
            yearlyCard,
            title: "Annual Plan",
            priceLabel: yearlyPriceLabel,
            fallbackPrice: "₹\(UsageTracker.yearlyPriceINR) per year",
            check: yearlyCheck,
            showSave: true
        )
        stylePlanCard(
            monthlyCard,
            title: "Monthly Plan",
            priceLabel: monthlyPriceLabel,
            fallbackPrice: "₹\(UsageTracker.monthlyPriceINR) per month",
            check: monthlyCheck,
            showSave: false
        )
        yearlyCard.addTarget(self, action: #selector(selectYearly), for: .touchUpInside)
        monthlyCard.addTarget(self, action: #selector(selectMonthly), for: .touchUpInside)

        let plans = UIStackView(arrangedSubviews: [yearlyCard, monthlyCard])
        plans.translatesAutoresizingMaskIntoConstraints = false
        plans.axis = .horizontal
        plans.spacing = 12
        plans.distribution = .fillEqually

        let payLabel = UILabel()
        payLabel.translatesAutoresizingMaskIntoConstraints = false
        payLabel.text = "PAYMENT METHOD"
        payLabel.font = .systemFont(ofSize: 12, weight: .heavy)
        payLabel.textColor = UIColor.black.withAlphaComponent(0.4)

        let payRow = UIView()
        payRow.translatesAutoresizingMaskIntoConstraints = false
        payRow.backgroundColor = .white
        payRow.layer.cornerRadius = 22

        let appleIcon = UIImageView(image: UIImage(systemName: "apple.logo"))
        appleIcon.translatesAutoresizingMaskIntoConstraints = false
        appleIcon.tintColor = onyx
        appleIcon.contentMode = .scaleAspectFit

        let payTitle = UILabel()
        payTitle.translatesAutoresizingMaskIntoConstraints = false
        payTitle.text = "App Store"
        payTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        payTitle.textColor = onyx

        let paySub = UILabel()
        paySub.translatesAutoresizingMaskIntoConstraints = false
        paySub.text = "In-App Purchase · GST included"
        paySub.font = .systemFont(ofSize: 12, weight: .medium)
        paySub.textColor = UIColor.black.withAlphaComponent(0.4)

        payRow.addSubview(appleIcon)
        payRow.addSubview(payTitle)
        payRow.addSubview(paySub)

        let termsRow = UIStackView()
        termsRow.translatesAutoresizingMaskIntoConstraints = false
        termsRow.axis = .horizontal
        termsRow.alignment = .top
        termsRow.spacing = 10

        agreeButton.translatesAutoresizingMaskIntoConstraints = false
        agreeButton.setImage(UIImage(systemName: "square"), for: .normal)
        agreeButton.tintColor = onyx
        agreeButton.addTarget(self, action: #selector(toggleAgree), for: .touchUpInside)

        let terms = UITextView()
        terms.translatesAutoresizingMaskIntoConstraints = false
        terms.isEditable = false
        terms.isScrollEnabled = false
        terms.backgroundColor = .clear
        terms.textContainerInset = .zero
        terms.textContainer.lineFragmentPadding = 0
        terms.delegate = self
        terms.attributedText = termsText()

        termsRow.addArrangedSubview(agreeButton)
        termsRow.addArrangedSubview(terms)

        payButton.translatesAutoresizingMaskIntoConstraints = false
        payButton.setTitleColor(.white, for: .normal)
        payButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        payButton.backgroundColor = onyx
        payButton.layer.cornerRadius = 22
        payButton.addTarget(self, action: #selector(confirmPay), for: .touchUpInside)

        let restore = UIButton(type: .system)
        restore.translatesAutoresizingMaskIntoConstraints = false
        restore.setTitle("Restore purchases", for: .normal)
        restore.setTitleColor(UIColor.black.withAlphaComponent(0.45), for: .normal)
        restore.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        restore.addTarget(self, action: #selector(restorePurchases), for: .touchUpInside)

        let later = UIButton(type: .system)
        later.translatesAutoresizingMaskIntoConstraints = false
        later.setTitle("Continue with Free", for: .normal)
        later.setTitleColor(UIColor.black.withAlphaComponent(0.45), for: .normal)
        later.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        later.addTarget(self, action: #selector(continueFreeFromOnboarding), for: .touchUpInside)
        later.isHidden = !isOnboarding

        let back = UIButton(type: .system)
        back.translatesAutoresizingMaskIntoConstraints = false
        back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        back.tintColor = onyx
        back.addTarget(self, action: #selector(goBack), for: .touchUpInside)

        view.addSubview(back)
        view.addSubview(title)
        view.addSubview(subtitle)
        view.addSubview(plans)
        view.addSubview(payLabel)
        view.addSubview(payRow)
        view.addSubview(termsRow)
        view.addSubview(payButton)
        view.addSubview(restore)
        view.addSubview(later)

        var bottomConstraints: [NSLayoutConstraint] = [
            agreeButton.widthAnchor.constraint(equalToConstant: 28),
            agreeButton.heightAnchor.constraint(equalToConstant: 28),
            payButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            payButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            payButton.heightAnchor.constraint(equalToConstant: 56),
            restore.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            later.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ]
        if isOnboarding {
            bottomConstraints.append(contentsOf: [
                later.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),
                restore.bottomAnchor.constraint(equalTo: later.topAnchor, constant: -2),
                payButton.bottomAnchor.constraint(equalTo: restore.topAnchor, constant: -8)
            ])
        } else {
            bottomConstraints.append(contentsOf: [
                restore.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),
                payButton.bottomAnchor.constraint(equalTo: restore.topAnchor, constant: -8)
            ])
        }

        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            back.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            back.widthAnchor.constraint(equalToConstant: 36),
            back.heightAnchor.constraint(equalToConstant: 36),

            title.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 8),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),

            plans.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 28),
            plans.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            plans.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            plans.heightAnchor.constraint(equalToConstant: 168),

            payLabel.topAnchor.constraint(equalTo: plans.bottomAnchor, constant: 28),
            payLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),

            payRow.topAnchor.constraint(equalTo: payLabel.bottomAnchor, constant: 12),
            payRow.leadingAnchor.constraint(equalTo: plans.leadingAnchor),
            payRow.trailingAnchor.constraint(equalTo: plans.trailingAnchor),
            payRow.heightAnchor.constraint(equalToConstant: 72),

            appleIcon.leadingAnchor.constraint(equalTo: payRow.leadingAnchor, constant: 18),
            appleIcon.centerYAnchor.constraint(equalTo: payRow.centerYAnchor),
            appleIcon.widthAnchor.constraint(equalToConstant: 28),
            appleIcon.heightAnchor.constraint(equalToConstant: 28),

            payTitle.leadingAnchor.constraint(equalTo: appleIcon.trailingAnchor, constant: 12),
            payTitle.topAnchor.constraint(equalTo: payRow.topAnchor, constant: 16),
            paySub.leadingAnchor.constraint(equalTo: payTitle.leadingAnchor),
            paySub.topAnchor.constraint(equalTo: payTitle.bottomAnchor, constant: 2),

            termsRow.topAnchor.constraint(equalTo: payRow.bottomAnchor, constant: 20),
            termsRow.leadingAnchor.constraint(equalTo: plans.leadingAnchor),
            termsRow.trailingAnchor.constraint(equalTo: plans.trailingAnchor)
        ] + bottomConstraints)
    }

    private func stylePlanCard(
        _ card: UIControl,
        title: String,
        priceLabel: UILabel,
        fallbackPrice: String,
        check: UIImageView,
        showSave: Bool
    ) {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor.white.withAlphaComponent(0.55)
        card.layer.cornerRadius = 24
        card.layer.borderWidth = 3
        card.layer.borderColor = UIColor.clear.cgColor

        let name = UILabel()
        name.translatesAutoresizingMaskIntoConstraints = false
        name.text = title
        name.font = .systemFont(ofSize: 16, weight: .semibold)
        name.textColor = onyx

        priceLabel.translatesAutoresizingMaskIntoConstraints = false
        priceLabel.text = fallbackPrice
        priceLabel.font = .systemFont(ofSize: 13, weight: .medium)
        priceLabel.textColor = UIColor.black.withAlphaComponent(0.45)
        priceLabel.numberOfLines = 2

        check.translatesAutoresizingMaskIntoConstraints = false
        check.contentMode = .scaleAspectFit
        check.tintColor = onyx

        card.addSubview(name)
        card.addSubview(priceLabel)
        card.addSubview(check)

        var topAnchor: NSLayoutYAxisAnchor = card.topAnchor
        var topConstant: CGFloat = 18

        if showSave {
            let badge = UILabel()
            badge.translatesAutoresizingMaskIntoConstraints = false
            badge.text = "  SAVE \(UsageTracker.yearlySavingsPercent)%  "
            badge.font = .systemFont(ofSize: 10, weight: .heavy)
            badge.textColor = onyx
            badge.backgroundColor = lime
            badge.layer.cornerRadius = 8
            badge.clipsToBounds = true
            card.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
                badge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14)
            ])
            topAnchor = badge.bottomAnchor
            topConstant = 10
        }

        NSLayoutConstraint.activate([
            name.topAnchor.constraint(equalTo: topAnchor, constant: topConstant),
            name.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            name.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            priceLabel.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 6),
            priceLabel.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            priceLabel.trailingAnchor.constraint(equalTo: name.trailingAnchor),
            check.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            check.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            check.widthAnchor.constraint(equalToConstant: 26),
            check.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    private func termsText() -> NSAttributedString {
        let full = "I have read and agree to B-easy Terms and Conditions and Privacy Policy.\nMaine B-easy ke Niyam aur Privacy Policy padh liye hain."
        let attr = NSMutableAttributedString(
            string: full,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: UIColor.black.withAlphaComponent(0.55)
            ]
        )
        let termsRange = (full as NSString).range(of: "Terms and Conditions")
        let privacyRange = (full as NSString).range(of: "Privacy Policy")
        attr.addAttributes([
            .link: URL(string: "https://souravgupta2111.github.io/Ledgile/terms.html")!,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: onyx
        ], range: termsRange)
        attr.addAttributes([
            .link: URL(string: "https://souravgupta2111.github.io/Ledgile/privacy-policy.html")!,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: onyx
        ], range: privacyRange)
        return attr
    }

    private func refreshSelection() {
        let yearlyOn = selected == .yearly
        yearlyCard.layer.borderColor = yearlyOn ? lime.cgColor : UIColor.clear.cgColor
        monthlyCard.layer.borderColor = yearlyOn ? UIColor.clear.cgColor : lime.cgColor
        yearlyCard.backgroundColor = yearlyOn ? .white : UIColor.white.withAlphaComponent(0.45)
        monthlyCard.backgroundColor = yearlyOn ? UIColor.white.withAlphaComponent(0.45) : .white
        yearlyCheck.image = UIImage(systemName: yearlyOn ? "checkmark.circle.fill" : "circle")
        monthlyCheck.image = UIImage(systemName: yearlyOn ? "circle" : "checkmark.circle.fill")
        updatePayTitle()
    }

    private func updatePayTitle() {
        let price = selected == .yearly ? ProStore.shared.displayYearlyPrice : ProStore.shared.displayMonthlyPrice
        payButton.setTitle("Confirm and pay \(price)", for: .normal)
        payButton.alpha = agreed ? 1 : 0.45
        payButton.isEnabled = agreed
    }

    @objc private func selectYearly() {
        selected = .yearly
        refreshSelection()
    }

    @objc private func selectMonthly() {
        selected = .monthly
        refreshSelection()
    }

    @objc private func toggleAgree() {
        agreed.toggle()
        let image = agreed ? "checkmark.square.fill" : "square"
        agreeButton.setImage(UIImage(systemName: image), for: .normal)
        agreeButton.tintColor = agreed ? lime : onyx
        updatePayTitle()
    }

    @objc private func goBack() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func continueFreeFromOnboarding() {
        AuthNavigationHelper.finishLaunchPlanAndGoToApp()
    }

    @objc private func restorePurchases() {
        Task { @MainActor in
            await ProStore.shared.restore()
            if UsageTracker.shared.isProUser {
                done("Pro restored.")
            } else {
                let alert = UIAlertController(title: "No purchase found", message: "No active B-easy Pro subscription is on this Apple ID.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }

    @objc private func confirmPay() {
        guard agreed else { return }
        Task { @MainActor in
            await ProStore.shared.refresh()
            let product = selected == .yearly ? ProStore.shared.yearlyProduct : ProStore.shared.monthlyProduct
            guard let product else {
                let alert = UIAlertController(
                    title: "Subscriptions not live yet",
                    message: "Create Auto-Renewable Subscriptions in App Store Connect:\n\(UsageTracker.monthlyProductID)\n\(UsageTracker.yearlyProductID)\n\nPrices: ₹\(UsageTracker.monthlyPriceINR) / month and ₹\(UsageTracker.yearlyPriceINR) / year.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                return
            }
            do {
                try await ProStore.shared.purchase(product)
                if UsageTracker.shared.isProUser {
                    done("Welcome to B-easy Pro.")
                }
            } catch {
                let alert = UIAlertController(title: "Purchase failed", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }

    private func done(_ message: String) {
        let alert = UIAlertController(title: "B-easy Pro", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            if self?.isOnboarding == true {
                AuthNavigationHelper.finishLaunchPlanAndGoToApp()
            } else {
                self?.navigationController?.dismiss(animated: true)
            }
        })
        present(alert, animated: true)
    }
}

extension ProPlanViewController: UITextViewDelegate {
    func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        let safari = SFSafariViewController(url: URL)
        present(safari, animated: true)
        return false
    }
}
