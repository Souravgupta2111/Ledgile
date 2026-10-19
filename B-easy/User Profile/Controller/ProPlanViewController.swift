import UIKit
import SafariServices

/// Plan picker + Apple IAP checkout. Matches B-easy Lime Moss / Beige / Onyx design system.
final class ProPlanViewController: UIViewController {

    var isOnboarding = false

    private enum Plan { case yearly, monthly }

    private let greenAccent = UIColor(red: 99/255, green: 140/255, blue: 0/255, alpha: 1.0) // #638C00
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
            let yPrice = ProStore.shared.displayYearlyPrice == "₹1999" ? "₹1,999" : ProStore.shared.displayYearlyPrice
            let mPrice = ProStore.shared.displayMonthlyPrice
            yearlyPriceLabel.attributedText = makePriceAttributed(price: yPrice, period: " / year")
            monthlyPriceLabel.attributedText = makePriceAttributed(price: mPrice, period: " / month")
            updatePayTitle()
        }
    }

    private func makePriceAttributed(price: String, period: String) -> NSAttributedString {
        let attr = NSMutableAttributedString(
            string: price,
            attributes: [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: onyx
            ]
        )
        let periodAttr = NSAttributedString(
            string: period,
            attributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: .regular),
                .foregroundColor: UIColor.black.withAlphaComponent(0.55)
            ]
        )
        attr.append(periodAttr)
        return attr
    }

    private func build() {
        // Back navigation button
        let back = UIButton(type: .system)
        back.translatesAutoresizingMaskIntoConstraints = false
        back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        back.tintColor = onyx
        back.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        view.addSubview(back)

        // Scroll view to prevent clipping on smaller devices while keeping layout anchored
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        // Title & Subtitle
        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Choose a plan"
        title.font = .systemFont(ofSize: 32, weight: .bold)
        title.textColor = onyx

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = "You can pay monthly or annually."
        subtitle.font = .systemFont(ofSize: 16, weight: .regular)
        subtitle.textColor = UIColor.black.withAlphaComponent(0.55)

        // Plan Cards (Vertical Stack of horizontal rows)
        yearlyPriceLabel.attributedText = makePriceAttributed(price: "₹1,999", period: " / year")
        monthlyPriceLabel.attributedText = makePriceAttributed(price: "₹199", period: " / month")

        stylePlanCard(
            yearlyCard,
            title: "Annual Plan",
            priceLabel: yearlyPriceLabel,
            check: yearlyCheck,
            isYearly: true
        )
        stylePlanCard(
            monthlyCard,
            title: "Monthly Plan",
            priceLabel: monthlyPriceLabel,
            check: monthlyCheck,
            isYearly: false
        )
        yearlyCard.addTarget(self, action: #selector(selectYearly), for: .touchUpInside)
        monthlyCard.addTarget(self, action: #selector(selectMonthly), for: .touchUpInside)

        let plans = UIStackView(arrangedSubviews: [yearlyCard, monthlyCard])
        plans.translatesAutoresizingMaskIntoConstraints = false
        plans.axis = .vertical
        plans.spacing = 12
        plans.distribution = .fillEqually

        // Payment Method Header
        let payLabel = UILabel()
        payLabel.translatesAutoresizingMaskIntoConstraints = false
        payLabel.text = "PAYMENT METHOD"
        payLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        payLabel.textColor = UIColor.black.withAlphaComponent(0.45)

        // Payment Method Card
        let payRow = UIView()
        payRow.translatesAutoresizingMaskIntoConstraints = false
        payRow.backgroundColor = .white
        payRow.layer.cornerRadius = 18

        let appleIcon = UIImageView(image: UIImage(systemName: "apple.logo"))
        appleIcon.translatesAutoresizingMaskIntoConstraints = false
        appleIcon.tintColor = onyx
        appleIcon.contentMode = .scaleAspectFit

        let payTextStack = UIStackView()
        payTextStack.translatesAutoresizingMaskIntoConstraints = false
        payTextStack.axis = .vertical
        payTextStack.spacing = 1

        let payTitle = UILabel()
        payTitle.translatesAutoresizingMaskIntoConstraints = false
        payTitle.text = "App Store"
        payTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        payTitle.textColor = onyx

        let paySub = UILabel()
        paySub.translatesAutoresizingMaskIntoConstraints = false
        paySub.text = "In-App Purchase · GST included"
        paySub.font = .systemFont(ofSize: 12, weight: .regular)
        paySub.textColor = UIColor.black.withAlphaComponent(0.45)

        payTextStack.addArrangedSubview(payTitle)
        payTextStack.addArrangedSubview(paySub)

        payRow.addSubview(appleIcon)
        payRow.addSubview(payTextStack)

        // Terms and Consent Row
        let termsRow = UIStackView()
        termsRow.translatesAutoresizingMaskIntoConstraints = false
        termsRow.axis = .horizontal
        termsRow.alignment = .top
        termsRow.spacing = 10

        agreeButton.translatesAutoresizingMaskIntoConstraints = false
        agreeButton.setImage(UIImage(systemName: "square"), for: .normal)
        agreeButton.tintColor = onyx.withAlphaComponent(0.6)
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
        terms.linkTextAttributes = [
            .foregroundColor: UIColor(red: 0/255, green: 122/255, blue: 255/255, alpha: 1.0),
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        termsRow.addArrangedSubview(agreeButton)
        termsRow.addArrangedSubview(terms)

        // Bottom CTA Actions Container
        let bottomContainer = UIStackView()
        bottomContainer.translatesAutoresizingMaskIntoConstraints = false
        bottomContainer.axis = .vertical
        bottomContainer.spacing = 10
        bottomContainer.alignment = .fill

        payButton.translatesAutoresizingMaskIntoConstraints = false
        payButton.setTitleColor(.white, for: .normal)
        payButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        payButton.backgroundColor = onyx
        payButton.layer.cornerRadius = 24
        payButton.clipsToBounds = true
        payButton.addTarget(self, action: #selector(confirmPay), for: .touchUpInside)

        let later = UIButton(type: .system)
        later.translatesAutoresizingMaskIntoConstraints = false
        later.setTitle("Continue with Free", for: .normal)
        later.setTitleColor(onyx, for: .normal)
        later.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        later.backgroundColor = .clear
        later.layer.cornerRadius = 24
        later.layer.borderWidth = 1.0
        later.layer.borderColor = UIColor.black.withAlphaComponent(0.22).cgColor
        later.clipsToBounds = true
        later.addTarget(self, action: #selector(continueFreeFromOnboarding), for: .touchUpInside)

        let restore = UIButton(type: .system)
        restore.translatesAutoresizingMaskIntoConstraints = false
        restore.setTitle("Restore purchases", for: .normal)
        restore.setTitleColor(UIColor.black.withAlphaComponent(0.5), for: .normal)
        restore.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
        restore.addTarget(self, action: #selector(restorePurchases), for: .touchUpInside)

        bottomContainer.addArrangedSubview(payButton)
        bottomContainer.addArrangedSubview(later)
        bottomContainer.addArrangedSubview(restore)

        contentView.addSubview(title)
        contentView.addSubview(subtitle)
        contentView.addSubview(plans)
        contentView.addSubview(payLabel)
        contentView.addSubview(payRow)
        contentView.addSubview(termsRow)
        contentView.addSubview(bottomContainer)

        let contentMinHeightConstraint = contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor)
        contentMinHeightConstraint.priority = .defaultLow

        NSLayoutConstraint.activate([
            // Back button
            back.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            back.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            back.widthAnchor.constraint(equalToConstant: 36),
            back.heightAnchor.constraint(equalToConstant: 36),

            // Scroll View
            scrollView.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentMinHeightConstraint,

            // Screen Title & Subtitle
            title.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            title.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            // Plan Cards Stack
            plans.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 18),
            plans.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            plans.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            yearlyCard.heightAnchor.constraint(equalToConstant: 88),
            monthlyCard.heightAnchor.constraint(equalToConstant: 88),

            // Payment Method Section
            payLabel.topAnchor.constraint(equalTo: plans.bottomAnchor, constant: 20),
            payLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),

            payRow.topAnchor.constraint(equalTo: payLabel.bottomAnchor, constant: 8),
            payRow.leadingAnchor.constraint(equalTo: plans.leadingAnchor),
            payRow.trailingAnchor.constraint(equalTo: plans.trailingAnchor),
            payRow.heightAnchor.constraint(equalToConstant: 58),

            appleIcon.leadingAnchor.constraint(equalTo: payRow.leadingAnchor, constant: 16),
            appleIcon.centerYAnchor.constraint(equalTo: payRow.centerYAnchor),
            appleIcon.widthAnchor.constraint(equalToConstant: 24),
            appleIcon.heightAnchor.constraint(equalToConstant: 24),

            payTextStack.leadingAnchor.constraint(equalTo: appleIcon.trailingAnchor, constant: 12),
            payTextStack.centerYAnchor.constraint(equalTo: payRow.centerYAnchor),
            payTextStack.trailingAnchor.constraint(lessThanOrEqualTo: payRow.trailingAnchor, constant: -16),

            // Terms and Consent
            termsRow.topAnchor.constraint(equalTo: payRow.bottomAnchor, constant: 16),
            termsRow.leadingAnchor.constraint(equalTo: plans.leadingAnchor),
            termsRow.trailingAnchor.constraint(equalTo: plans.trailingAnchor),

            agreeButton.widthAnchor.constraint(equalToConstant: 22),
            agreeButton.heightAnchor.constraint(equalToConstant: 22),

            // Bottom Actions (Anchored at bottom with flexible spacing from terms)
            bottomContainer.topAnchor.constraint(greaterThanOrEqualTo: termsRow.bottomAnchor, constant: 22),
            bottomContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            bottomContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            bottomContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),

            payButton.heightAnchor.constraint(equalToConstant: 52),
            later.heightAnchor.constraint(equalToConstant: 50),
            restore.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func stylePlanCard(
        _ card: UIControl,
        title: String,
        priceLabel: UILabel,
        check: UIImageView,
        isYearly: Bool
    ) {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 20
        card.layer.borderWidth = 1
        card.clipsToBounds = true

        // Left text stack (Title + Price)
        let textStack = UIStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.alignment = .leading
        textStack.isUserInteractionEnabled = false

        let nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.text = title
        nameLabel.font = .systemFont(ofSize: 18, weight: .regular)
        nameLabel.textColor = onyx

        priceLabel.translatesAutoresizingMaskIntoConstraints = false
        priceLabel.numberOfLines = 1

        textStack.addArrangedSubview(nameLabel)
        textStack.addArrangedSubview(priceLabel)

        check.translatesAutoresizingMaskIntoConstraints = false
        check.contentMode = .scaleAspectFit
        check.isUserInteractionEnabled = false

        card.addSubview(textStack)
        card.addSubview(check)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            textStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -12),

            check.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            check.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 25),
            check.heightAnchor.constraint(equalToConstant: 25)
        ])

        if isYearly {
            let badge = UILabel()
            badge.translatesAutoresizingMaskIntoConstraints = false
            badge.text = "SAVE ₹\(UsageTracker.yearlySavingsINR)/YEAR"
            badge.font = .systemFont(ofSize: 11.5, weight: .bold)
            badge.textColor = .white
            badge.backgroundColor = greenAccent
            badge.textAlignment = .center
            badge.layer.cornerRadius = 14
            badge.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMinXMinYCorner]
            badge.clipsToBounds = true

            card.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.topAnchor.constraint(equalTo: card.topAnchor),
                badge.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                badge.heightAnchor.constraint(equalToConstant: 26),
                badge.widthAnchor.constraint(equalToConstant: 140)
            ])
        }
    }

    private func termsText() -> NSAttributedString {
        let full = "I have read and agree to B-easy Terms and Conditions and Privacy Policy."
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = 20
        paragraphStyle.maximumLineHeight = 20
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attr = NSMutableAttributedString(
            string: full,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.black.withAlphaComponent(0.55),
                .paragraphStyle: paragraphStyle
            ]
        )
        let termsRange = (full as NSString).range(of: "Terms and Conditions")
        let privacyRange = (full as NSString).range(of: "Privacy Policy")
        let linkBlue = UIColor(red: 0/255, green: 122/255, blue: 255/255, alpha: 1.0)
        attr.addAttributes([
            .link: URL(string: "https://souravgupta2111.github.io/Ledgile/terms.html")!,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: linkBlue
        ], range: termsRange)
        attr.addAttributes([
            .link: URL(string: "https://souravgupta2111.github.io/Ledgile/privacy-policy.html")!,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: linkBlue
        ], range: privacyRange)
        return attr
    }

    private func refreshSelection() {
        let yearlyOn = selected == .yearly

        let unselectedBg = UIColor(red: 245/255, green: 243/255, blue: 224/255, alpha: 1.0)
        let unselectedBorder = UIColor.black.withAlphaComponent(0.08).cgColor

        yearlyCard.backgroundColor = yearlyOn ? .white : unselectedBg
        yearlyCard.layer.borderWidth = yearlyOn ? 2.0 : 1.0
        yearlyCard.layer.borderColor = yearlyOn ? greenAccent.cgColor : unselectedBorder
        
        let checkConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        yearlyCheck.image = UIImage(
            systemName: yearlyOn ? "checkmark.circle.fill" : "circle",
            withConfiguration: checkConfig
        )
        yearlyCheck.tintColor = yearlyOn ? greenAccent : UIColor.black.withAlphaComponent(0.35)

        monthlyCard.backgroundColor = yearlyOn ? unselectedBg : .white
        monthlyCard.layer.borderWidth = yearlyOn ? 1.0 : 2.0
        monthlyCard.layer.borderColor = yearlyOn ? unselectedBorder : greenAccent.cgColor
        monthlyCheck.image = UIImage(
            systemName: yearlyOn ? "circle" : "checkmark.circle.fill",
            withConfiguration: checkConfig
        )
        monthlyCheck.tintColor = yearlyOn ? UIColor.black.withAlphaComponent(0.35) : greenAccent

        updatePayTitle()
    }

    private func updatePayTitle() {
        let rawPrice = selected == .yearly ? ProStore.shared.displayYearlyPrice : ProStore.shared.displayMonthlyPrice
        let price = (selected == .yearly && rawPrice == "₹1999") ? "₹1,999" : rawPrice
        payButton.setTitle("Confirm and pay \(price)", for: .normal)
        let disabledBg = UIColor(red: 140/255, green: 140/255, blue: 114/255, alpha: 1.0)
        payButton.backgroundColor = agreed ? onyx : disabledBg
        payButton.isEnabled = agreed
    }

    @objc private func selectYearly() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selected = .yearly
        refreshSelection()
    }

    @objc private func selectMonthly() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selected = .monthly
        refreshSelection()
    }

    @objc private func toggleAgree() {
        agreed.toggle()
        let image = agreed ? "checkmark.square.fill" : "square"
        agreeButton.setImage(UIImage(systemName: image), for: .normal)
        agreeButton.tintColor = agreed ? greenAccent : onyx.withAlphaComponent(0.6)
        updatePayTitle()
    }

    @objc private func goBack() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func continueFreeFromOnboarding() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if isOnboarding {
            AuthNavigationHelper.finishLaunchPlanAndGoToApp()
        } else {
            if presentingViewController != nil {
                dismiss(animated: true)
            } else {
                navigationController?.popViewController(animated: true)
            }
        }
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
