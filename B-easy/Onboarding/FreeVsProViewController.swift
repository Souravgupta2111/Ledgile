import UIKit

/// Onboarding Plan Selection Screen matching B-easy design system (Beige background, white card with comparison matrix).
final class FreeVsProViewController: UIViewController {

    private let lime = UIColor(named: "Lime Moss") ?? UIColor(red: 0.41, green: 0.56, blue: 0.0, alpha: 1.0)
    private let beige = UIColor(named: "Beige") ?? UIColor(red: 0.91, green: 0.90, blue: 0.76, alpha: 1.0)
    private let onyx = UIColor(named: "Onyx") ?? UIColor(red: 0.05, green: 0.07, blue: 0.05, alpha: 1.0)

    private enum FeatureAccess {
        case included   // ✅ green checkmark — full access
        case basic      // ⚡ orange bolt — works but basic/on-device
        case excluded   // ❌ gray X — not available
    }

    private struct FeatureItem {
        let iconName: String
        let title: String
        let subtitle: String
        let freeAccess: FeatureAccess
        let proAccess: FeatureAccess
    }

    private let features: [FeatureItem] = [
        FeatureItem(
            iconName: "doc.text.fill",
            title: "Billing & Credit Ledger",
            subtitle: "Create bills, track sales and manage credit",
            freeAccess: .included,
            proAccess: .included
        ),
        FeatureItem(
            iconName: "waveform.and.mic",
            title: "Voice Entry",
            subtitle: "Add sales by speaking",
            freeAccess: .basic,
            proAccess: .included
        ),
        FeatureItem(
            iconName: "camera.viewfinder",
            title: "Bill & Barcode Scanner",
            subtitle: "Scan bills and product barcodes",
            freeAccess: .basic,
            proAccess: .included
        ),
        FeatureItem(
            iconName: "icloud.and.arrow.up.fill",
            title: "Cloud Backup & Sync",
            subtitle: "Back up your data and access it across devices",
            freeAccess: .included,
            proAccess: .included
        ),
        FeatureItem(
            iconName: "chart.bar.doc.horizontal",
            title: "GST & Tax Reports",
            subtitle: "Get GST reports to share with your CA",
            freeAccess: .excluded,
            proAccess: .included
        ),
        FeatureItem(
            iconName: "cpu.fill",
            title: "AI Business Assistant",
            subtitle: "Get answers about sales, stock and business trends",
            freeAccess: .excluded,
            proAccess: .included
        )
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = beige
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.setNavigationBarHidden(true, animated: false)
        buildUI()
    }

    private func buildUI() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.clipsToBounds = true
        view.addSubview(scrollView)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        // Bottom CTA Container
        let bottomContainer = UIView()
        bottomContainer.translatesAutoresizingMaskIntoConstraints = false
        bottomContainer.backgroundColor = .clear
        view.addSubview(bottomContainer)

        let upgradeButton = UIButton(type: .system)
        upgradeButton.translatesAutoresizingMaskIntoConstraints = false
        upgradeButton.configuration = nil
        upgradeButton.backgroundColor = onyx
        upgradeButton.setTitle("See Pro plans", for: .normal)
        upgradeButton.setTitleColor(.white, for: .normal)
        upgradeButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        upgradeButton.layer.cornerRadius = 24
        upgradeButton.clipsToBounds = true
        upgradeButton.addTarget(self, action: #selector(seeProPlans), for: .touchUpInside)

        let priceNote = UILabel()
        priceNote.translatesAutoresizingMaskIntoConstraints = false
        priceNote.text = "From ₹\(UsageTracker.monthlyPriceINR)/month · Cancel anytime"
        priceNote.font = .systemFont(ofSize: 13, weight: .medium)
        priceNote.textColor = UIColor.black.withAlphaComponent(0.55)
        priceNote.textAlignment = .center

        let continueStarterButton = UIButton(type: .system)
        continueStarterButton.translatesAutoresizingMaskIntoConstraints = false
        continueStarterButton.setTitle("Continue with Free", for: .normal)
        continueStarterButton.setTitleColor(onyx, for: .normal)
        continueStarterButton.titleLabel?.font = .systemFont(ofSize: 16.5, weight: .bold)
        continueStarterButton.backgroundColor = .clear
        continueStarterButton.layer.cornerRadius = 24
        continueStarterButton.layer.borderWidth = 1.0
        continueStarterButton.layer.borderColor = UIColor.black.withAlphaComponent(0.25).cgColor
        continueStarterButton.clipsToBounds = true
        continueStarterButton.addTarget(self, action: #selector(continueFree), for: .touchUpInside)

        bottomContainer.addSubview(upgradeButton)
        bottomContainer.addSubview(priceNote)
        bottomContainer.addSubview(continueStarterButton)

        // --- Screen Header: Title & Subtitle ---
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "How do you want to use\nB-easy?"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = onyx
        titleLabel.numberOfLines = 2

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Manage your shop for free. Upgrade to Pro for\nmore scans and extra features."
        subtitleLabel.font = .systemFont(ofSize: 14.5, weight: .regular)
        subtitleLabel.textColor = UIColor.black.withAlphaComponent(0.55)
        subtitleLabel.numberOfLines = 2

        // --- White Comparison Card ---
        let cardView = UIView()
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .white
        cardView.layer.cornerRadius = 24
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.05
        cardView.layer.shadowOffset = CGSize(width: 0, height: 3)
        cardView.layer.shadowRadius = 10

        // --- Card Header Row ---
        let headerRow = UIView()
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        let headerTitle = UILabel()
        headerTitle.translatesAutoresizingMaskIntoConstraints = false
        headerTitle.text = "What's included"
        headerTitle.font = .systemFont(ofSize: 13.5, weight: .semibold)
        headerTitle.textColor = UIColor.black.withAlphaComponent(0.45)

        let starterHeader = UILabel()
        starterHeader.translatesAutoresizingMaskIntoConstraints = false
        starterHeader.text = "Free"
        starterHeader.font = .systemFont(ofSize: 14.5, weight: .bold)
        starterHeader.textColor = onyx
        starterHeader.textAlignment = .center

        let unlimitedPill = UIView()
        unlimitedPill.translatesAutoresizingMaskIntoConstraints = false
        unlimitedPill.backgroundColor = lime.withAlphaComponent(0.18)
        unlimitedPill.layer.cornerRadius = 12
        unlimitedPill.clipsToBounds = true

        let unlimitedLabel = UILabel()
        unlimitedLabel.translatesAutoresizingMaskIntoConstraints = false
        unlimitedLabel.text = "Pro"
        unlimitedLabel.font = .systemFont(ofSize: 13.5, weight: .bold)
        unlimitedLabel.textColor = UIColor(red: 0.18, green: 0.42, blue: 0.15, alpha: 1.0)
        unlimitedLabel.textAlignment = .center

        unlimitedPill.addSubview(unlimitedLabel)

        headerRow.addSubview(headerTitle)
        headerRow.addSubview(starterHeader)
        headerRow.addSubview(unlimitedPill)

        let headerDivider = UIView()
        headerDivider.translatesAutoresizingMaskIntoConstraints = false
        headerDivider.backgroundColor = UIColor.black.withAlphaComponent(0.06)

        // --- Feature Rows Stack inside Card ---
        let featuresStack = UIStackView()
        featuresStack.translatesAutoresizingMaskIntoConstraints = false
        featuresStack.axis = .vertical
        featuresStack.spacing = 8

        for (index, item) in features.enumerated() {
            let row = makeFeatureRow(item: item)
            featuresStack.addArrangedSubview(row)

            if index < features.count - 1 {
                let rowDivider = UIView()
                rowDivider.translatesAutoresizingMaskIntoConstraints = false
                rowDivider.backgroundColor = UIColor.black.withAlphaComponent(0.04)
                rowDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true
                featuresStack.addArrangedSubview(rowDivider)
            }
        }

        // --- Legend Bar inside Card ---
        let legendBar = makeLegendBar()

        cardView.addSubview(headerRow)
        cardView.addSubview(headerDivider)
        cardView.addSubview(featuresStack)
        cardView.addSubview(legendBar)

        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(cardView)

        let colUnlimitedWidth: CGFloat = 54
        let colStarterWidth: CGFloat = 52

        NSLayoutConstraint.activate([
            // Bottom Container
            bottomContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            bottomContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            bottomContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            upgradeButton.topAnchor.constraint(equalTo: bottomContainer.topAnchor),
            upgradeButton.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
            upgradeButton.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor),
            upgradeButton.heightAnchor.constraint(equalToConstant: 52),

            priceNote.topAnchor.constraint(equalTo: upgradeButton.bottomAnchor, constant: 12),
            priceNote.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
            priceNote.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor),

            continueStarterButton.topAnchor.constraint(equalTo: priceNote.bottomAnchor, constant: 12),
            continueStarterButton.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
            continueStarterButton.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor),
            continueStarterButton.heightAnchor.constraint(equalToConstant: 50),
            continueStarterButton.bottomAnchor.constraint(equalTo: bottomContainer.bottomAnchor),

            // Scroll View
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomContainer.topAnchor, constant: -12),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -8),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            // Title & Subtitle Layout
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            // Card Container
            cardView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Card Header Layout
            headerRow.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            headerRow.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            headerRow.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            headerRow.heightAnchor.constraint(equalToConstant: 26),

            headerTitle.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            headerTitle.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            headerTitle.trailingAnchor.constraint(lessThanOrEqualTo: starterHeader.leadingAnchor, constant: -8),

            unlimitedPill.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor),
            unlimitedPill.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            unlimitedPill.widthAnchor.constraint(equalToConstant: colUnlimitedWidth),
            unlimitedPill.heightAnchor.constraint(equalToConstant: 24),

            unlimitedLabel.centerXAnchor.constraint(equalTo: unlimitedPill.centerXAnchor),
            unlimitedLabel.centerYAnchor.constraint(equalTo: unlimitedPill.centerYAnchor),

            starterHeader.trailingAnchor.constraint(equalTo: unlimitedPill.leadingAnchor, constant: -12),
            starterHeader.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            starterHeader.widthAnchor.constraint(equalToConstant: colStarterWidth),

            headerDivider.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 8),
            headerDivider.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            headerDivider.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            headerDivider.heightAnchor.constraint(equalToConstant: 1),

            // Features Stack inside Card
            featuresStack.topAnchor.constraint(equalTo: headerDivider.bottomAnchor, constant: 8),
            featuresStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            featuresStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),

            // Legend inside Card
            legendBar.topAnchor.constraint(equalTo: featuresStack.bottomAnchor, constant: 10),
            legendBar.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            legendBar.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            legendBar.heightAnchor.constraint(equalToConstant: 38),
            legendBar.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12)
        ])
    }

    private func makeLegendBar() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor(red: 0.93, green: 0.93, blue: 0.88, alpha: 1.0)
        container.layer.cornerRadius = 13
        container.clipsToBounds = true

        let item1 = makeLegendItem(
            systemName: "checkmark.circle.fill",
            tintColor: lime,
            text: "= Included"
        )
        let item2 = makeLegendItem(
            systemName: "bolt.circle.fill",
            tintColor: UIColor(red: 0.95, green: 0.62, blue: 0.14, alpha: 1.0),
            text: "= Limited"
        )
        let item3 = makeLegendItem(
            systemName: "xmark.circle.fill",
            tintColor: UIColor(red: 0.68, green: 0.70, blue: 0.72, alpha: 1.0),
            text: "= Not available"
        )

        let stack = UIStackView(arrangedSubviews: [item1, item2, item3])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: 38)
        ])

        return container
    }

    private func makeLegendItem(systemName: String, tintColor: UIColor, text: String) -> UIView {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 5

        let icon = UIImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        icon.image = UIImage(systemName: systemName, withConfiguration: config)
        icon.tintColor = tintColor
        icon.contentMode = .scaleAspectFit

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = .systemFont(ofSize: 11.5, weight: .medium)
        label.textColor = UIColor.black.withAlphaComponent(0.65)

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16)
        ])

        return stack
    }

    private func makeFeatureRow(item: FeatureItem) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        iconView.image = UIImage(systemName: item.iconName, withConfiguration: iconConfig)
        iconView.tintColor = onyx
        iconView.contentMode = .scaleAspectFit
        iconContainer.addSubview(iconView)

        let textStack = UIStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 1

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = item.title
        titleLabel.font = .systemFont(ofSize: 14.5, weight: .bold)
        titleLabel.textColor = onyx
        titleLabel.numberOfLines = 1

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = item.subtitle
        subtitleLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        subtitleLabel.textColor = UIColor.black.withAlphaComponent(0.55)
        subtitleLabel.numberOfLines = 2

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)

        let starterIcon = makeStatusIcon(access: item.freeAccess)
        let unlimitedIcon = makeStatusIcon(access: item.proAccess)

        let starterWrap = UIView()
        starterWrap.translatesAutoresizingMaskIntoConstraints = false
        starterWrap.addSubview(starterIcon)

        let unlimitedWrap = UIView()
        unlimitedWrap.translatesAutoresizingMaskIntoConstraints = false
        unlimitedWrap.addSubview(unlimitedIcon)

        row.addSubview(iconContainer)
        row.addSubview(textStack)
        row.addSubview(starterWrap)
        row.addSubview(unlimitedWrap)

        let colUnlimitedWidth: CGFloat = 54
        let colStarterWidth: CGFloat = 52

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            iconContainer.topAnchor.constraint(equalTo: row.topAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 24),
            iconContainer.heightAnchor.constraint(equalToConstant: 24),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            textStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 8),
            textStack.topAnchor.constraint(equalTo: row.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: starterWrap.leadingAnchor, constant: -6),

            unlimitedWrap.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            unlimitedWrap.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            unlimitedWrap.widthAnchor.constraint(equalToConstant: colUnlimitedWidth),

            unlimitedIcon.centerXAnchor.constraint(equalTo: unlimitedWrap.centerXAnchor),
            unlimitedIcon.centerYAnchor.constraint(equalTo: unlimitedWrap.centerYAnchor),

            starterWrap.trailingAnchor.constraint(equalTo: unlimitedWrap.leadingAnchor, constant: -12),
            starterWrap.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            starterWrap.widthAnchor.constraint(equalToConstant: colStarterWidth),

            starterIcon.centerXAnchor.constraint(equalTo: starterWrap.centerXAnchor),
            starterIcon.centerYAnchor.constraint(equalTo: starterWrap.centerYAnchor)
        ])

        return row
    }

    private func makeStatusIcon(access: FeatureAccess) -> UIView {
        let size: CGFloat = 20
        let imgView = UIImageView()
        imgView.translatesAutoresizingMaskIntoConstraints = false

        switch access {
        case .included:
            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
            imgView.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)
            imgView.tintColor = lime
        case .basic:
            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            imgView.image = UIImage(systemName: "bolt.circle.fill", withConfiguration: config)
            imgView.tintColor = UIColor(red: 0.95, green: 0.62, blue: 0.14, alpha: 1.0)
        case .excluded:
            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            imgView.image = UIImage(systemName: "xmark.circle.fill", withConfiguration: config)
            imgView.tintColor = UIColor(red: 0.68, green: 0.70, blue: 0.72, alpha: 1.0)
        }

        imgView.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([
            imgView.widthAnchor.constraint(equalToConstant: size),
            imgView.heightAnchor.constraint(equalToConstant: size)
        ])
        return imgView
    }

    // MARK: - Actions

    @objc private func continueFree() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        AuthNavigationHelper.finishLaunchPlanAndGoToApp()
    }

    @objc private func seeProPlans() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let vc = ProPlanViewController()
        vc.isOnboarding = true
        navigationController?.pushViewController(vc, animated: true)
    }
}
