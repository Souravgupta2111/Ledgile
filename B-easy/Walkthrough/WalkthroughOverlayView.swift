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
        view.layer.cornerRadius = 20
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.22
        view.layer.shadowRadius = 14
        view.layer.shadowOffset = CGSize(width: 0, height: 6)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let headerStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let stepBadgeContainer: UIView = {
        let view = UIView()
        let lime = UIColor(named: "Lime Moss") ?? UIColor(red: 0.13, green: 0.75, blue: 0.42, alpha: 1.0)
        view.backgroundColor = lime.withAlphaComponent(0.15)
        view.layer.cornerRadius = 10
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
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 14.5, weight: .regular)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let buttonStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 12
        stack.distribution = .fillProportionally
        stack.alignment = .fill
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

    // Pre-created positioning constraints to prevent constraint leaking
    private var cardCenterYConstraint: NSLayoutConstraint!
    private var cardTopConstraint: NSLayoutConstraint!
    private var cardBottomConstraint: NSLayoutConstraint!

    private var currentSpotlightRect: CGRect?
    private var currentStep: WalkthroughStep = .welcome

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
        backgroundColor = UIColor.black.withAlphaComponent(0.55)
        isUserInteractionEnabled = true

        dimmingMaskLayer.fillRule = .evenOdd
        layer.mask = dimmingMaskLayer

        let lime = UIColor(named: "Lime Moss") ?? UIColor(red: 0.13, green: 0.75, blue: 0.42, alpha: 1.0)
        spotlightGlowLayer.strokeColor = lime.withAlphaComponent(0.70).cgColor
        spotlightGlowLayer.fillColor = UIColor.clear.cgColor
        spotlightGlowLayer.lineWidth = 1.5
        spotlightGlowLayer.lineDashPattern = nil
        spotlightGlowLayer.shadowColor = nil
        spotlightGlowLayer.shadowOpacity = 0
        spotlightGlowLayer.shadowRadius = 0
        spotlightGlowLayer.shadowOffset = .zero
        layer.addSublayer(spotlightGlowLayer)

        addSubview(cardView)

        // Setup badge container
        stepBadgeContainer.addSubview(stepBadgeLabel)
        NSLayoutConstraint.activate([
            stepBadgeLabel.topAnchor.constraint(equalTo: stepBadgeContainer.topAnchor, constant: 4),
            stepBadgeLabel.bottomAnchor.constraint(equalTo: stepBadgeContainer.bottomAnchor, constant: -4),
            stepBadgeLabel.leadingAnchor.constraint(equalTo: stepBadgeContainer.leadingAnchor, constant: 10),
            stepBadgeLabel.trailingAnchor.constraint(equalTo: stepBadgeContainer.trailingAnchor, constant: -10)
        ])

        stepBadgeContainer.setContentHuggingPriority(.required, for: .vertical)
        stepBadgeContainer.setContentCompressionResistancePriority(.required, for: .vertical)
        stepBadgeContainer.setContentHuggingPriority(.required, for: .horizontal)
        stepBadgeLabel.setContentHuggingPriority(.required, for: .vertical)
        stepBadgeLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        // Setup header stack
        headerStack.addArrangedSubview(stepBadgeContainer)
        headerStack.addArrangedSubview(skipButton)

        // Setup button stack
        buttonStack.addArrangedSubview(backButton)
        buttonStack.addArrangedSubview(primaryButton)

        // Setup vertical content stack
        contentStackView.addArrangedSubview(headerStack)
        contentStackView.addArrangedSubview(titleLabel)
        contentStackView.addArrangedSubview(messageLabel)
        contentStackView.addArrangedSubview(buttonStack)

        contentStackView.setCustomSpacing(10, after: titleLabel)
        contentStackView.setCustomSpacing(18, after: messageLabel)

        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        messageLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        messageLabel.setContentHuggingPriority(.defaultLow, for: .vertical)

        cardView.addSubview(contentStackView)
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 18),
            contentStackView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            contentStackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            contentStackView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -18),
            buttonStack.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Card positioning constraints
        let cardWidth = cardView.widthAnchor.constraint(equalTo: widthAnchor, constant: -40)
        cardWidth.priority = UILayoutPriority(950)
        let cardMaxWidth = cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 400)
        let cardMinWidth = cardView.widthAnchor.constraint(greaterThanOrEqualToConstant: 280)
        let cardCenterX = cardView.centerXAnchor.constraint(equalTo: centerXAnchor)

        // Boundaries to prevent offscreen layout
        let safeTop = cardView.topAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor, constant: 16)
        let safeBottom = cardView.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -16)

        cardCenterYConstraint = cardView.centerYAnchor.constraint(equalTo: centerYAnchor)
        cardTopConstraint = cardView.topAnchor.constraint(equalTo: topAnchor, constant: 100)
        cardBottomConstraint = cardView.bottomAnchor.constraint(equalTo: topAnchor, constant: 400)

        NSLayoutConstraint.activate([
            cardCenterX,
            cardWidth,
            cardMaxWidth,
            cardMinWidth,
            safeTop,
            safeBottom
        ])

        cardCenterYConstraint.isActive = true
        cardTopConstraint.isActive = false
        cardBottomConstraint.isActive = false

        setupActions()
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
        currentStep = step

        updateSpotlightAndCardPosition(targetRect: targetRect, step: step, isModal: step.isModal, animated: animated)
    }

    /// Recalculates and smoothly updates the spotlight target frame during runtime without reconfiguring content.
    func updateTargetRect(_ targetRect: CGRect?, for step: WalkthroughStep? = nil, animated: Bool = true) {
        let activeStep = step ?? currentStep
        guard targetRect != currentSpotlightRect else { return }
        updateSpotlightAndCardPosition(targetRect: targetRect, step: activeStep, isModal: activeStep.isModal, animated: animated)
    }

    private func updateSpotlightAndCardPosition(
        targetRect: CGRect?,
        step: WalkthroughStep,
        isModal: Bool,
        animated: Bool
    ) {
        currentSpotlightRect = targetRect

        let boundsPath = UIBezierPath(rect: bounds)

        if let target = targetRect, !isModal {
            let cornerRadius = step.spotlightCornerRadius
            let cutoutPath = UIBezierPath(roundedRect: target, cornerRadius: cornerRadius)
            boundsPath.append(cutoutPath)

            let glowPath = UIBezierPath(roundedRect: target, cornerRadius: cornerRadius).cgPath

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

            repositionCard(relativeTo: target, animated: animated)
        } else {
            if animated {
                let maskAnim = CABasicAnimation(keyPath: "path")
                maskAnim.fromValue = dimmingMaskLayer.path
                maskAnim.toValue = boundsPath.cgPath
                maskAnim.duration = 0.25
                dimmingMaskLayer.add(maskAnim, forKey: "pathAnimation")
            }
            dimmingMaskLayer.path = boundsPath.cgPath
            spotlightGlowLayer.isHidden = true

            centerCard(animated: animated)
        }
    }

    private func repositionCard(relativeTo target: CGRect, animated: Bool) {
        let screenHeight = bounds.height
        let safeTopBound = safeAreaInsets.top + 16
        let safeBottomBound = screenHeight - safeAreaInsets.bottom - 16

        let spaceAbove = target.minY - safeTopBound
        let spaceBelow = safeBottomBound - target.maxY

        let shouldPlaceBelow: Bool
        if spaceBelow >= 260 {
            shouldPlaceBelow = true
        } else if spaceAbove >= 260 {
            shouldPlaceBelow = false
        } else {
            shouldPlaceBelow = (spaceBelow >= spaceAbove)
        }

        let spacing: CGFloat = 12

        if shouldPlaceBelow {
            let topY = target.maxY + spacing
            cardTopConstraint.constant = topY
            cardBottomConstraint.isActive = false
            cardCenterYConstraint.isActive = false
            cardTopConstraint.isActive = true
        } else {
            let bottomY = target.minY - spacing
            cardBottomConstraint.constant = bottomY
            cardTopConstraint.isActive = false
            cardCenterYConstraint.isActive = false
            cardBottomConstraint.isActive = true
        }

        if animated {
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                usingSpringWithDamping: 0.88,
                initialSpringVelocity: 0.3,
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
        cardTopConstraint.isActive = false
        cardBottomConstraint.isActive = false
        cardCenterYConstraint.isActive = true

        if animated {
            UIView.animate(
                withDuration: 0.28,
                delay: 0,
                usingSpringWithDamping: 0.88,
                initialSpringVelocity: 0.3,
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
    }
}
