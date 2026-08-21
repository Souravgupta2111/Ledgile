import UIKit
import SafariServices

/// First paywall screen: benefits carousel, then plan picker.
final class ProBenefitsViewController: UIViewController {

    private let lime = UIColor(named: "Lime Moss") ?? .systemGreen
    private let beige = UIColor(named: "Beige") ?? UIColor(red: 0.91, green: 0.90, blue: 0.76, alpha: 1)
    private let onyx = UIColor(named: "Onyx") ?? UIColor(red: 0.05, green: 0.07, blue: 0, alpha: 1)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = beige
        navigationItem.largeTitleDisplayMode = .never
        build()
    }

    private func build() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.showsVerticalScrollIndicator = false
        view.addSubview(scroll)

        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)

        let brandRow = UIStackView()
        brandRow.axis = .horizontal
        brandRow.alignment = .center
        brandRow.spacing = 10
        brandRow.translatesAutoresizingMaskIntoConstraints = false

        let brand = UILabel()
        brand.text = "B-easy"
        brand.font = .systemFont(ofSize: 28, weight: .bold)
        brand.textColor = onyx

        let proBadge = UILabel()
        proBadge.text = "  PRO  "
        proBadge.font = .systemFont(ofSize: 12, weight: .heavy)
        proBadge.textColor = onyx
        proBadge.backgroundColor = lime
        proBadge.layer.cornerRadius = 8
        proBadge.clipsToBounds = true

        brandRow.addArrangedSubview(brand)
        brandRow.addArrangedSubview(proBadge)
        let brandSpacer = UIView()
        brandRow.addArrangedSubview(brandSpacer)

        let headline = UILabel()
        headline.translatesAutoresizingMaskIntoConstraints = false
        headline.text = "Get exclusive benefits with B-easy Pro."
        headline.font = .systemFont(ofSize: 28, weight: .bold)
        headline.textColor = onyx
        headline.numberOfLines = 0

        let sub = UILabel()
        sub.translatesAutoresizingMaskIntoConstraints = false
        sub.text = "₹\(UsageTracker.monthlyPriceINR) per month. ₹\(UsageTracker.yearlyPriceINR) per year — save \(UsageTracker.yearlySavingsPercent)%."
        sub.font = .systemFont(ofSize: 15, weight: .medium)
        sub.textColor = UIColor.black.withAlphaComponent(0.45)
        sub.numberOfLines = 0

        let benefitsLabel = UILabel()
        benefitsLabel.translatesAutoresizingMaskIntoConstraints = false
        benefitsLabel.text = "PREMIUM BENEFITS"
        benefitsLabel.font = .systemFont(ofSize: 12, weight: .heavy)
        benefitsLabel.textColor = UIColor.black.withAlphaComponent(0.4)

        let carousel = UIScrollView()
        carousel.translatesAutoresizingMaskIntoConstraints = false
        carousel.showsHorizontalScrollIndicator = false
        carousel.alwaysBounceHorizontal = true

        let cards = UIStackView()
        cards.translatesAutoresizingMaskIntoConstraints = false
        cards.axis = .horizontal
        cards.spacing = 14
        carousel.addSubview(cards)

        let voiceCard = benefitCard(
            symbol: "waveform",
            title: "\(UsageTracker.proVoiceScansPerDay) voice scans",
            subtitle: "Every day"
        )
        let cameraCard = benefitCard(
            symbol: "camera.fill",
            title: "\(UsageTracker.proCameraScansPerDay) photo scans",
            subtitle: "Bills & products"
        )
        let backupCard = benefitCard(
            symbol: "icloud.fill",
            title: "Cloud backup",
            subtitle: "Keep the ledger safe"
        )
        cards.addArrangedSubview(voiceCard)
        cards.addArrangedSubview(cameraCard)
        cards.addArrangedSubview(backupCard)

        let choose = UIButton(type: .system)
        choose.translatesAutoresizingMaskIntoConstraints = false
        choose.setTitle("Choose your Plan", for: .normal)
        choose.setTitleColor(.white, for: .normal)
        choose.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        choose.backgroundColor = onyx
        choose.layer.cornerRadius = 22
        choose.addTarget(self, action: #selector(choosePlan), for: .touchUpInside)

        let notNow = UIButton(type: .system)
        notNow.translatesAutoresizingMaskIntoConstraints = false
        notNow.setTitle("Not Now", for: .normal)
        notNow.setTitleColor(UIColor.black.withAlphaComponent(0.45), for: .normal)
        notNow.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        notNow.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)

        content.addSubview(brandRow)
        content.addSubview(headline)
        content.addSubview(sub)
        content.addSubview(benefitsLabel)
        content.addSubview(carousel)
        view.addSubview(choose)
        view.addSubview(notNow)

        let cardWidth: CGFloat = 210
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: choose.topAnchor, constant: -16),

            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),

            brandRow.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            brandRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            brandRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            headline.topAnchor.constraint(equalTo: brandRow.bottomAnchor, constant: 28),
            headline.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            headline.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            sub.topAnchor.constraint(equalTo: headline.bottomAnchor, constant: 10),
            sub.leadingAnchor.constraint(equalTo: headline.leadingAnchor),
            sub.trailingAnchor.constraint(equalTo: headline.trailingAnchor),

            benefitsLabel.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 36),
            benefitsLabel.leadingAnchor.constraint(equalTo: headline.leadingAnchor),

            carousel.topAnchor.constraint(equalTo: benefitsLabel.bottomAnchor, constant: 14),
            carousel.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            carousel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            carousel.heightAnchor.constraint(equalToConstant: 280),
            carousel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),

            cards.topAnchor.constraint(equalTo: carousel.contentLayoutGuide.topAnchor),
            cards.bottomAnchor.constraint(equalTo: carousel.contentLayoutGuide.bottomAnchor),
            cards.leadingAnchor.constraint(equalTo: carousel.contentLayoutGuide.leadingAnchor, constant: 24),
            cards.trailingAnchor.constraint(equalTo: carousel.contentLayoutGuide.trailingAnchor, constant: -24),
            cards.heightAnchor.constraint(equalTo: carousel.frameLayoutGuide.heightAnchor),

            voiceCard.widthAnchor.constraint(equalToConstant: cardWidth),
            cameraCard.widthAnchor.constraint(equalToConstant: cardWidth),
            backupCard.widthAnchor.constraint(equalToConstant: cardWidth),

            notNow.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            notNow.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            choose.bottomAnchor.constraint(equalTo: notNow.topAnchor, constant: -10),
            choose.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            choose.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            choose.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    private func benefitCard(symbol: String, title: String, subtitle: String) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = onyx
        card.layer.cornerRadius = 28

        let iconWrap = UIView()
        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.backgroundColor = lime.withAlphaComponent(0.22)
        iconWrap.layer.cornerRadius = 36

        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = lime
        icon.contentMode = .scaleAspectFit
        iconWrap.addSubview(icon)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2

        let subLabel = UILabel()
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        subLabel.text = subtitle
        subLabel.font = .systemFont(ofSize: 13, weight: .medium)
        subLabel.textColor = UIColor.white.withAlphaComponent(0.55)

        card.addSubview(iconWrap)
        card.addSubview(titleLabel)
        card.addSubview(subLabel)

        NSLayoutConstraint.activate([
            iconWrap.topAnchor.constraint(equalTo: card.topAnchor, constant: 36),
            iconWrap.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            iconWrap.widthAnchor.constraint(equalToConstant: 72),
            iconWrap.heightAnchor.constraint(equalToConstant: 72),

            icon.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            titleLabel.bottomAnchor.constraint(equalTo: subLabel.topAnchor, constant: -4),

            subLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22)
        ])
        return card
    }

    @objc private func choosePlan() {
        navigationController?.pushViewController(ProPlanViewController(), animated: true)
    }

    @objc private func dismissSelf() {
        if presentingViewController != nil {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    static func present(from presenter: UIViewController) {
        let vc = ProBenefitsViewController()
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen
        nav.setNavigationBarHidden(true, animated: false)
        presenter.present(nav, animated: true)
    }
}
