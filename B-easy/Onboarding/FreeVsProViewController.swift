import UIKit

/// Shown once after first login: pick Free or continue to Pro monthly/yearly.
final class FreeVsProViewController: UIViewController {

    private let lime = UIColor(named: "Lime Moss") ?? .systemGreen
    private let beige = UIColor(named: "Beige") ?? UIColor(red: 0.91, green: 0.90, blue: 0.76, alpha: 1)
    private let onyx = UIColor(named: "Onyx") ?? UIColor(red: 0.05, green: 0.07, blue: 0, alpha: 1)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = beige
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.setNavigationBarHidden(true, animated: false)
        build()
    }

    private func build() {
        let headline = UILabel()
        headline.translatesAutoresizingMaskIntoConstraints = false
        headline.text = "How do you want to use B-easy?"
        headline.font = .systemFont(ofSize: 28, weight: .bold)
        headline.textColor = onyx
        headline.numberOfLines = 0

        let sub = UILabel()
        sub.translatesAutoresizingMaskIntoConstraints = false
        sub.text = "The ledger is free. Voice and photo scans are limited unless you choose Pro."
        sub.font = .systemFont(ofSize: 15, weight: .medium)
        sub.textColor = UIColor.black.withAlphaComponent(0.45)
        sub.numberOfLines = 0

        let freeCard = choiceCard(
            title: "Free",
            price: "₹0",
            points: [
                "Full sales, stock, GST, and UPI",
                "\(UsageTracker.freeGeminiLimit) voice & photo scans, lifetime",
                "Then on-device voice and bill scanner"
            ],
            emphasized: false,
            actionTitle: "Continue with Free",
            action: #selector(continueFree)
        )

        let proCard = choiceCard(
            title: "Pro",
            price: "From ₹\(UsageTracker.monthlyPriceINR)/mo",
            points: [
                "\(UsageTracker.proVoiceScansPerDay) voice scans every day",
                "\(UsageTracker.proCameraScansPerDay) photo scans every day",
                "Then on-device until tomorrow"
            ],
            emphasized: true,
            actionTitle: "See Pro plans",
            action: #selector(seeProPlans)
        )

        let stack = UIStackView(arrangedSubviews: [freeCard, proCard])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14

        view.addSubview(headline)
        view.addSubview(sub)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            headline.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            headline.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            headline.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            sub.topAnchor.constraint(equalTo: headline.bottomAnchor, constant: 8),
            sub.leadingAnchor.constraint(equalTo: headline.leadingAnchor),
            sub.trailingAnchor.constraint(equalTo: headline.trailingAnchor),

            stack.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func choiceCard(
        title: String,
        price: String,
        points: [String],
        emphasized: Bool,
        actionTitle: String,
        action: Selector
    ) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .white
        card.layer.cornerRadius = 24
        card.layer.borderWidth = emphasized ? 3 : 0
        card.layer.borderColor = emphasized ? lime.cgColor : UIColor.clear.cgColor

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = onyx

        let priceLabel = UILabel()
        priceLabel.translatesAutoresizingMaskIntoConstraints = false
        priceLabel.text = price
        priceLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        priceLabel.textColor = emphasized ? lime : UIColor.black.withAlphaComponent(0.45)

        let pointsStack = UIStackView()
        pointsStack.translatesAutoresizingMaskIntoConstraints = false
        pointsStack.axis = .vertical
        pointsStack.spacing = 6
        for point in points {
            let row = UILabel()
            row.text = "  \(point)"
            row.font = .systemFont(ofSize: 14, weight: .medium)
            row.textColor = UIColor.black.withAlphaComponent(0.62)
            row.numberOfLines = 0
            pointsStack.addArrangedSubview(row)
        }

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(actionTitle, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.layer.cornerRadius = 18
        button.addTarget(self, action: action, for: .touchUpInside)
        if emphasized {
            button.backgroundColor = onyx
            button.setTitleColor(.white, for: .normal)
        } else {
            button.backgroundColor = beige
            button.setTitleColor(onyx, for: .normal)
        }

        card.addSubview(titleLabel)
        card.addSubview(priceLabel)
        card.addSubview(pointsStack)
        card.addSubview(button)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            priceLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            priceLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            pointsStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            pointsStack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pointsStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            button.topAnchor.constraint(equalTo: pointsStack.bottomAnchor, constant: 18),
            button.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            button.heightAnchor.constraint(equalToConstant: 48),
            button.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])
        return card
    }

    @objc private func continueFree() {
        AuthNavigationHelper.finishLaunchPlanAndGoToApp()
    }

    @objc private func seeProPlans() {
        let vc = ProPlanViewController()
        vc.isOnboarding = true
        navigationController?.pushViewController(vc, animated: true)
    }
}
