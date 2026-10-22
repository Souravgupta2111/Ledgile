import UIKit

protocol WalkthroughOverlayViewDelegate: AnyObject {
    func walkthroughOverlayDidTapNext(_ overlay: WalkthroughOverlayView)
    func walkthroughOverlayDidTapBack(_ overlay: WalkthroughOverlayView)
    func walkthroughOverlayDidTapSkip(_ overlay: WalkthroughOverlayView)
}

/// Represents an individual spotlight cutout shape in the dimming overlay.
struct WalkthroughCutout: Equatable {
    let rect: CGRect
    let cornerRadius: CGFloat

    init(rect: CGRect, cornerRadius: CGFloat) {
        self.rect = rect
        self.cornerRadius = cornerRadius
    }
}

final class WalkthroughOverlayView: UIView {

    weak var delegate: WalkthroughOverlayViewDelegate?

    // MARK: - Brand Colors

    private static var brandGreen: UIColor {
        UIColor(named: "Lime Moss") ?? UIColor(red: 105/255, green: 143/255, blue: 0/255, alpha: 1.0)
    }

    // MARK: - Subviews & Layers

    private let dimmingMaskLayer = CAShapeLayer()

    private let cardView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 20
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 0.5
        view.layer.borderColor = UIColor.separator.withAlphaComponent(0.20).cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.10
        view.layer.shadowRadius = 14
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let headerStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let headerSpacer: UIView = {
        let view = UIView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let stepBadgeContainer: UIView = {
        let view = UIView()
        view.backgroundColor = WalkthroughOverlayView.brandGreen.withAlphaComponent(0.12)
        view.layer.cornerRadius = 11
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let stepBadgeLabel: UILabel = {
        let label = UILabel()
        label.textColor = WalkthroughOverlayView.brandGreen
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let skipButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Skip Tour", for: .normal)
        button.setTitleColor(.secondaryLabel, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .label
        label.font = .systemFont(ofSize: 19.5, weight: .bold)
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
        stack.spacing = 10
        stack.distribution = .fill
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let backButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = .tertiarySystemFill
        config.baseForegroundColor = .label
        config.cornerStyle = .fixed
        config.background.cornerRadius = 13
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        var titleAttr = AttributedString("Back")
        titleAttr.font = .systemFont(ofSize: 15, weight: .semibold)
        config.attributedTitle = titleAttr
        let button = UIButton(configuration: config)
        button.layer.cornerCurve = .continuous
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let primaryButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = WalkthroughOverlayView.brandGreen
        config.baseForegroundColor = .white
        config.cornerStyle = .fixed
        config.background.cornerRadius = 13
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
        var titleAttr = AttributedString("Next")
        titleAttr.font = .systemFont(ofSize: 15, weight: .semibold)
        config.attributedTitle = titleAttr
        let button = UIButton(configuration: config)
        button.layer.cornerCurve = .continuous
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // Pre-created positioning constraints to prevent constraint leaking
    private var cardCenterYConstraint: NSLayoutConstraint!
    private var cardTopConstraint: NSLayoutConstraint!
    private var cardBottomConstraint: NSLayoutConstraint!
    private var backButtonWidthConstraint: NSLayoutConstraint!

    private(set) var activeCutouts: [WalkthroughCutout] = []
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
        backgroundColor = UIColor.black.withAlphaComponent(0.54)
        isUserInteractionEnabled = true

        dimmingMaskLayer.fillRule = .evenOdd
        layer.mask = dimmingMaskLayer

        addSubview(cardView)

        // Setup badge container
        stepBadgeContainer.addSubview(stepBadgeLabel)
        NSLayoutConstraint.activate([
            stepBadgeContainer.heightAnchor.constraint(equalToConstant: 22),
            stepBadgeLabel.centerYAnchor.constraint(equalTo: stepBadgeContainer.centerYAnchor),
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
        headerStack.addArrangedSubview(headerSpacer)
        headerStack.addArrangedSubview(skipButton)

        // Setup button stack
        buttonStack.addArrangedSubview(backButton)
        buttonStack.addArrangedSubview(primaryButton)

        backButtonWidthConstraint = backButton.widthAnchor.constraint(equalToConstant: 88)

        // Setup vertical content stack
        contentStackView.addArrangedSubview(headerStack)
        contentStackView.addArrangedSubview(titleLabel)
        contentStackView.addArrangedSubview(messageLabel)
        contentStackView.addArrangedSubview(buttonStack)

        contentStackView.setCustomSpacing(8, after: titleLabel)
        contentStackView.setCustomSpacing(16, after: messageLabel)

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
        let cardMaxWidth = cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 356)
        let cardMinWidth = cardView.widthAnchor.constraint(greaterThanOrEqualToConstant: 280)
        let cardCenterX = cardView.centerXAnchor.constraint(equalTo: centerXAnchor)

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

    /// Backward-compatible configure with single optional targetRect.
    func configure(
        step: WalkthroughStep,
        targetRect: CGRect?,
        canGoBack: Bool,
        animated: Bool = true
    ) {
        let cutouts: [WalkthroughCutout]
        if let rect = targetRect, !step.isModal {
            cutouts = [WalkthroughCutout(rect: rect, cornerRadius: step.spotlightCornerRadius)]
        } else {
            cutouts = []
        }
        configure(step: step, cutouts: cutouts, canGoBack: canGoBack, animated: animated)
    }

    /// Full configure method supporting one or multiple precise cutouts.
    func configure(
        step: WalkthroughStep,
        cutouts: [WalkthroughCutout],
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
        titleAttr.font = .systemFont(ofSize: 15, weight: .semibold)
        primaryButton.configuration?.attributedTitle = titleAttr

        backButton.isHidden = !canGoBack
        backButtonWidthConstraint.isActive = canGoBack

        let badgeText: String?
        if let index = step.stepIndex {
            badgeText = "STEP \(index) OF \(WalkthroughStep.totalGuidedSteps)"
        } else if step == .welcome {
            badgeText = "WELCOME"
        } else if step == .completion {
            badgeText = "ALL SET"
        } else {
            badgeText = nil
        }

        if let text = badgeText {
            stepBadgeContainer.isHidden = false
            let attr = NSMutableAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: Self.brandGreen,
                    .kern: 0.6
                ]
            )
            stepBadgeLabel.attributedText = attr
        } else {
            stepBadgeContainer.isHidden = true
        }

        skipButton.isHidden = (step == .completion)
        currentStep = step

        updateCutoutsAndCardPosition(cutouts: cutouts, step: step, isModal: step.isModal, animated: animated)
    }

    /// Backward-compatible single target rect update.
    func updateTargetRect(_ targetRect: CGRect?, for step: WalkthroughStep? = nil, animated: Bool = true) {
        let activeStep = step ?? currentStep
        let cutouts: [WalkthroughCutout]
        if let rect = targetRect, !activeStep.isModal {
            cutouts = [WalkthroughCutout(rect: rect, cornerRadius: activeStep.spotlightCornerRadius)]
        } else {
            cutouts = []
        }
        updateCutouts(cutouts, for: activeStep, animated: animated)
    }

    /// Dynamically updates the spotlight cutouts during runtime without resetting content.
    func updateCutouts(_ cutouts: [WalkthroughCutout], for step: WalkthroughStep? = nil, animated: Bool = true) {
        let activeStep = step ?? currentStep
        guard cutouts != activeCutouts else { return }
        updateCutoutsAndCardPosition(cutouts: cutouts, step: activeStep, isModal: activeStep.isModal, animated: animated)
    }

    private func updateCutoutsAndCardPosition(
        cutouts: [WalkthroughCutout],
        step: WalkthroughStep,
        isModal: Bool,
        animated: Bool
    ) {
        activeCutouts = cutouts

        let targetBgColor = isModal ? UIColor.black.withAlphaComponent(0.54) : UIColor.black.withAlphaComponent(0.44)
        if animated {
            UIView.animate(withDuration: 0.28) {
                self.backgroundColor = targetBgColor
            }
        } else {
            self.backgroundColor = targetBgColor
        }

        let boundsPath = UIBezierPath(rect: bounds)

        if !cutouts.isEmpty && !isModal {
            for cutout in cutouts {
                let cutoutPath = UIBezierPath(roundedRect: cutout.rect, cornerRadius: cutout.cornerRadius)
                boundsPath.append(cutoutPath)
            }

            if animated {
                let maskAnim = CABasicAnimation(keyPath: "path")
                maskAnim.fromValue = dimmingMaskLayer.path
                maskAnim.toValue = boundsPath.cgPath
                maskAnim.duration = 0.28
                maskAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                dimmingMaskLayer.add(maskAnim, forKey: "pathAnimation")
            }

            dimmingMaskLayer.path = boundsPath.cgPath

            // Position card relative to the composite bounding box of all cutouts
            let boundingBox = cutouts.reduce(CGRect.null) { $0.isNull ? $1.rect : $0.union($1.rect) }
            repositionCard(relativeTo: boundingBox, for: step, animated: animated)
        } else {
            if animated {
                let maskAnim = CABasicAnimation(keyPath: "path")
                maskAnim.fromValue = dimmingMaskLayer.path
                maskAnim.toValue = boundsPath.cgPath
                maskAnim.duration = 0.25
                dimmingMaskLayer.add(maskAnim, forKey: "pathAnimation")
            }
            dimmingMaskLayer.path = boundsPath.cgPath

            centerCard(animated: animated)
        }
    }

    private func repositionCard(relativeTo target: CGRect, for step: WalkthroughStep, animated: Bool) {
        let screenHeight = bounds.height
        let safeTopBound = safeAreaInsets.top + 16
        // Bottom limit accounts for bottom tab bar (49pt) + safeArea bottom + margin (16pt)
        let safeBottomBound = screenHeight - safeAreaInsets.bottom - 49 - 16

        if step == .dashboardOverview {
            // In Dashboard Overview, anchor tooltip cleanly at the bottom above the tab bar
            // so it never awkwardly slices through the credit cards or crowds the screen.
            let bottomY = safeBottomBound
            cardBottomConstraint.constant = bottomY
            cardTopConstraint.isActive = false
            cardCenterYConstraint.isActive = false
            cardBottomConstraint.isActive = true
        } else {
            let spaceAbove = target.minY - safeTopBound
            let spaceBelow = safeBottomBound - target.maxY

            // Prefer placing above when target is in the middle or lower section of screen
            let shouldPlaceBelow: Bool
            if target.minY < screenHeight * 0.38 && spaceBelow >= 220 {
                shouldPlaceBelow = true
            } else if spaceAbove >= 200 {
                shouldPlaceBelow = false
            } else {
                shouldPlaceBelow = (spaceBelow >= spaceAbove)
            }

            let spacing: CGFloat = (step == .stockTab) ? 12 : 14

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
    }
}
