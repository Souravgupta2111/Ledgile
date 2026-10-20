import UIKit

protocol WalkthroughOverlayViewDelegate: AnyObject {
    func walkthroughOverlayDidTapNext(_ overlay: WalkthroughOverlayView)
    func walkthroughOverlayDidTapBack(_ overlay: WalkthroughOverlayView)
    func walkthroughOverlayDidTapSkip(_ overlay: WalkthroughOverlayView)
}

final class WalkthroughOverlayView: UIView {

    weak var delegate: WalkthroughOverlayViewDelegate?

    // MARK: - Subviews & Layers

    private let dimmingMaskLayer = CAShapeLayer()
    private let spotlightGlowLayer = CAShapeLayer()

    private let cardView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 22
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.25
        view.layer.shadowRadius = 16
        view.layer.shadowOffset = CGSize(width: 0, height: 6)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let stepBadgeContainer: UIView = {
        let view = UIView()
        let lime = UIColor(named: "Lime Moss") ?? UIColor(red: 0.13, green: 0.75, blue: 0.42, alpha: 1.0)
        view.backgroundColor = lime.withAlphaComponent(0.15)
        view.layer.cornerRadius = 12
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let stepBadgeLabel: UILabel = {
        let label = UILabel()
        let lime = UIColor(named: "Lime Moss") ?? UIColor(red: 0.13, green: 0.75, blue: 0.42, alpha: 1.0)
        label.textColor = lime
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let skipButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Skip Tour", for: .normal)
        button.setTitleColor(.secondaryLabel, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .label
        label.font = .systemFont(ofSize: 19, weight: .bold)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 14.5, weight: .regular)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let buttonStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 12
        stack.distribution = .fillProportionally
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let backButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = .tertiarySystemFill
        config.baseForegroundColor = .label
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)
        var titleAttr = AttributedString("Back")
        titleAttr.font = .systemFont(ofSize: 15, weight: .semibold)
        config.attributedTitle = titleAttr
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let primaryButton: UIButton = {
        let lime = UIColor(named: "Lime Moss") ?? UIColor(red: 0.13, green: 0.75, blue: 0.42, alpha: 1.0)
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = lime
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 24, bottom: 10, trailing: 24)
        var titleAttr = AttributedString("Next")
        titleAttr.font = .systemFont(ofSize: 15, weight: .bold)
        config.attributedTitle = titleAttr
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // Layout constraints for card position
    private var cardCenterXConstraint: NSLayoutConstraint?
    private var cardCenterYConstraint: NSLayoutConstraint?
    private var cardTopConstraint: NSLayoutConstraint?
    private var cardBottomConstraint: NSLayoutConstraint?
    private var cardLeadingConstraint: NSLayoutConstraint?
    private var cardTrailingConstraint: NSLayoutConstraint?

    private var currentSpotlightRect: CGRect?

    // MARK: - Initializer

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    // MARK: - Setup

    private func setupView() {
        backgroundColor = UIColor.black.withAlphaComponent(0.65)
        isUserInteractionEnabled = true

        dimmingMaskLayer.fillRule = .evenOdd
        layer.mask = dimmingMaskLayer

        let lime = UIColor(named: "Lime Moss") ?? UIColor(red: 0.13, green: 0.75, blue: 0.42, alpha: 1.0)
        spotlightGlowLayer.strokeColor = lime.cgColor
        spotlightGlowLayer.fillColor = UIColor.clear.cgColor
        spotlightGlowLayer.lineWidth = 2.5
        spotlightGlowLayer.lineDashPattern = [6, 4]
        layer.addSublayer(spotlightGlowLayer)

        addSubview(cardView)

        cardView.addSubview(stepBadgeContainer)
        stepBadgeContainer.addSubview(stepBadgeLabel)
        cardView.addSubview(skipButton)
        cardView.addSubview(titleLabel)
        cardView.addSubview(messageLabel)
        cardView.addSubview(buttonStack)

        buttonStack.addArrangedSubview(backButton)
        buttonStack.addArrangedSubview(primaryButton)

        setupStaticConstraints()
        setupActions()
    }

    private func setupStaticConstraints() {
        NSLayoutConstraint.activate([
            // Step badge
            stepBadgeContainer.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 18),
            stepBadgeContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            stepBadgeLabel.topAnchor.constraint(equalTo: stepBadgeContainer.topAnchor, constant: 4),
            stepBadgeLabel.bottomAnchor.constraint(equalTo: stepBadgeContainer.bottomAnchor, constant: -4),
            stepBadgeLabel.leadingAnchor.constraint(equalTo: stepBadgeContainer.leadingAnchor, constant: 10),
            stepBadgeLabel.trailingAnchor.constraint(equalTo: stepBadgeContainer.trailingAnchor, constant: -10),

            // Skip button
            skipButton.centerYAnchor.constraint(equalTo: stepBadgeContainer.centerYAnchor),
            skipButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),

            // Title
            titleLabel.topAnchor.constraint(equalTo: stepBadgeContainer.bottomAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),

            // Message
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            messageLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            messageLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),

            // Button stack
            buttonStack.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 20),
            buttonStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            buttonStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            buttonStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -18),
            buttonStack.heightAnchor.constraint(equalToConstant: 44),

            backButton.heightAnchor.constraint(equalToConstant: 44),
            primaryButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Width constraints for card
        cardLeadingConstraint = cardView.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: 20)
        cardTrailingConstraint = cardView.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -20)
        cardCenterXConstraint = cardView.centerXAnchor.constraint(equalTo: centerXAnchor)
        cardCenterYConstraint = cardView.centerYAnchor.constraint(equalTo: centerYAnchor)

        cardLeadingConstraint?.isActive = true
        cardTrailingConstraint?.isActive = true
        cardCenterXConstraint?.isActive = true
        cardCenterYConstraint?.isActive = true

        let widthConstraint = cardView.widthAnchor.constraint(equalTo: widthAnchor, constant: -40)
        widthConstraint.priority = .defaultHigh
        widthConstraint.isActive = true

        let maxWidthConstraint = cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        maxWidthConstraint.isActive = true
    }

    private func setupActions() {
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
    }

    @objc private func primaryTapped() {
        delegate?.walkthroughOverlayDidTapNext(self)
    }

    @objc private func backTapped() {
        delegate?.walkthroughOverlayDidTapBack(self)
    }

    @objc private func skipTapped() {
        delegate?.walkthroughOverlayDidTapSkip(self)
    }

    // MARK: - Update Content & Spotlight

    func configure(
        step: WalkthroughStep,
        targetRect: CGRect?,
        canGoBack: Bool,
        animated: Bool = true
    ) {
        titleLabel.text = step.title

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        let attributedMessage = NSAttributedString(
            string: step.message,
            attributes: [
                .paragraphStyle: paragraphStyle,
                .font: UIFont.systemFont(ofSize: 14.5, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel
            ]
        )
        messageLabel.attributedText = attributedMessage

        var titleAttr = AttributedString(step.primaryButtonTitle)
        titleAttr.font = .systemFont(ofSize: 15, weight: .bold)
        primaryButton.configuration?.attributedTitle = titleAttr
        backButton.isHidden = !canGoBack

        if let index = step.stepIndex {
            stepBadgeContainer.isHidden = false
            stepBadgeLabel.text = "Step \(index) of \(WalkthroughStep.totalGuidedSteps)"
        } else if step == .welcome {
            stepBadgeContainer.isHidden = false
            stepBadgeLabel.text = "✨ Welcome"
        } else if step == .completion {
            stepBadgeContainer.isHidden = false
            stepBadgeLabel.text = "🎉 Done"
        } else {
            stepBadgeContainer.isHidden = true
        }

        skipButton.isHidden = (step == .completion)

        updateSpotlightAndCardPosition(targetRect: targetRect, isModal: step.isModal, animated: animated)
    }

    private func updateSpotlightAndCardPosition(
        targetRect: CGRect?,
        isModal: Bool,
        animated: Bool
    ) {
        currentSpotlightRect = targetRect

        let boundsPath = UIBezierPath(rect: bounds)

        if let target = targetRect, !isModal {
            // Expand cutout slightly for breathing room
            let insetRect = target.insetBy(dx: -6, dy: -6)
            let cornerRadius: CGFloat = min(16, insetRect.height / 2)
            let cutoutPath = UIBezierPath(roundedRect: insetRect, cornerRadius: cornerRadius)
            boundsPath.append(cutoutPath)

            let glowPath = UIBezierPath(roundedRect: insetRect, cornerRadius: cornerRadius).cgPath

            if animated {
                let maskAnim = CABasicAnimation(keyPath: "path")
                maskAnim.fromValue = dimmingMaskLayer.path
                maskAnim.toValue = boundsPath.cgPath
                maskAnim.duration = 0.28
                maskAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                dimmingMaskLayer.add(maskAnim, forKey: "pathAnimation")

                let glowAnim = CABasicAnimation(keyPath: "path")
                glowAnim.fromValue = spotlightGlowLayer.path
                glowAnim.toValue = glowPath
                glowAnim.duration = 0.28
                glowAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                spotlightGlowLayer.add(glowAnim, forKey: "glowAnimation")
            }

            dimmingMaskLayer.path = boundsPath.cgPath
            spotlightGlowLayer.path = glowPath
            spotlightGlowLayer.isHidden = false

            // Position card relative to target
            repositionCard(relativeTo: insetRect, animated: animated)
        } else {
            // Full screen dimming for modal steps
            if animated {
                let maskAnim = CABasicAnimation(keyPath: "path")
                maskAnim.fromValue = dimmingMaskLayer.path
                maskAnim.toValue = boundsPath.cgPath
                maskAnim.duration = 0.25
                dimmingMaskLayer.add(maskAnim, forKey: "pathAnimation")
            }
            dimmingMaskLayer.path = boundsPath.cgPath
            spotlightGlowLayer.isHidden = true

            // Center card in screen
            centerCard(animated: animated)
        }
    }

    private func repositionCard(relativeTo target: CGRect, animated: Bool) {
        cardCenterYConstraint?.isActive = false
        cardTopConstraint?.isActive = false
        cardBottomConstraint?.isActive = false

        let screenHeight = bounds.height
        let screenCenterY = screenHeight / 2

        if target.midY < screenCenterY {
            // Target is in the upper half -> position card below target
            let topConstant = max(target.maxY + 16, safeAreaInsets.top + 16)
            cardTopConstraint = cardView.topAnchor.constraint(equalTo: topAnchor, constant: topConstant)
            cardTopConstraint?.isActive = true
        } else {
            // Target is in the lower half -> position card above target
            let bottomConstant = min(target.minY - 16, screenHeight - safeAreaInsets.bottom - 16)
            cardBottomConstraint = cardView.bottomAnchor.constraint(equalTo: topAnchor, constant: bottomConstant)
            cardBottomConstraint?.isActive = true
        }

        if animated {
            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0.4,
                options: [.curveEaseInOut, .beginFromCurrentState],
                animations: {
                    self.layoutIfNeeded()
                }
            )
        } else {
            layoutIfNeeded()
        }
    }

    private func centerCard(animated: Bool) {
        cardTopConstraint?.isActive = false
        cardBottomConstraint?.isActive = false
        cardCenterYConstraint = cardView.centerYAnchor.constraint(equalTo: centerYAnchor)
        cardCenterYConstraint?.isActive = true

        if animated {
            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0.4,
                options: [.curveEaseInOut, .beginFromCurrentState],
                animations: {
                    self.layoutIfNeeded()
                }
            )
        } else {
            layoutIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dimmingMaskLayer.frame = bounds
        spotlightGlowLayer.frame = bounds

        if let rect = currentSpotlightRect {
            updateSpotlightAndCardPosition(targetRect: rect, isModal: false, animated: false)
        }
    }
}
