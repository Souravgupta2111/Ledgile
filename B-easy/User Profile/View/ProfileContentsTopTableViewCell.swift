import UIKit

enum BusinessCardField {
    case shop
    case owner
    case phone
    case address
    case gstin
    case email
    case website
}

final class ProfileContentsTopTableViewCell: UITableViewCell {

    @IBOutlet private weak var profileImageView: UIImageView!
    @IBOutlet private weak var nameLabel: UILabel!
    @IBOutlet private weak var phoneLabel: UILabel!
    @IBOutlet private weak var editButton: UIButton!

    var onShareTapped: (() -> Void)?
    var onFieldTapped: ((BusinessCardField) -> Void)?

    private let cardView = BusinessCardShellView()
    private let patternView = BusinessCardPatternStrip()
    private let shareButton = UIButton(type: .system)
    private let shopLabel = UILabel()
    private let ownerLabel = UILabel()
    private let contactPhoneLabel = UILabel()
    private let addressLabel = UILabel()
    private let gstinLabel = UILabel()
    private let emailLabel = UILabel()
    private let websiteLabel = UILabel()
    private let contentStack = UIStackView()

    override func awakeFromNib() {
        super.awakeFromNib()
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        backgroundView = UIView()
        backgroundView?.backgroundColor = .clear
        backgroundConfiguration = .clear()

        contentView.constraints.forEach { $0.isActive = false }
        [profileImageView, nameLabel, phoneLabel, editButton].forEach {
            $0.constraints.forEach { $0.isActive = false }
            $0.isHidden = true
            $0.removeFromSuperview()
        }

        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        patternView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(patternView)

        configureInfoLabel(shopLabel, size: 20, weight: .bold, lines: 2)
        configureInfoLabel(ownerLabel, size: 16, weight: .semibold, lines: 1)
        configureInfoLabel(contactPhoneLabel, size: 14, weight: .medium, lines: 1)
        configureInfoLabel(addressLabel, size: 13, weight: .regular, lines: 2)
        configureInfoLabel(gstinLabel, size: 13, weight: .medium, lines: 1)
        configureInfoLabel(emailLabel, size: 13, weight: .regular, lines: 1)
        configureInfoLabel(websiteLabel, size: 13, weight: .semibold, lines: 1)

        shopLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapShop)))
        ownerLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapOwner)))
        contactPhoneLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapPhone)))
        addressLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapAddress)))
        gstinLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapGSTIN)))
        emailLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapEmail)))
        websiteLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapWebsite)))

        shareButton.translatesAutoresizingMaskIntoConstraints = false
        shareButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        shareButton.tintColor = .white
        shareButton.setTitle(nil, for: .normal)
        shareButton.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        shareButton.layer.cornerRadius = 14
        shareButton.clipsToBounds = true
        shareButton.accessibilityLabel = "Share business card"
        shareButton.addTarget(self, action: #selector(tapShare), for: .touchUpInside)

        let infoStack = UIStackView(arrangedSubviews: [
            shopLabel, ownerLabel, contactPhoneLabel, addressLabel, gstinLabel, emailLabel
        ])
        infoStack.axis = .vertical
        infoStack.alignment = .fill
        infoStack.spacing = 6
        infoStack.setCustomSpacing(10, after: contactPhoneLabel)

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(infoStack)
        contentStack.addArrangedSubview(websiteLabel)
        cardView.addSubview(contentStack)
        
        let cellGuide = UILayoutGuide()
        cardView.addLayoutGuide(cellGuide)
        cardView.addSubview(shareButton)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            cardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 168),

            patternView.topAnchor.constraint(equalTo: cardView.topAnchor),
            patternView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            patternView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            patternView.widthAnchor.constraint(equalTo: cardView.widthAnchor, multiplier: 0.28),

            cellGuide.trailingAnchor.constraint(equalTo: patternView.trailingAnchor),
            cellGuide.topAnchor.constraint(equalTo: patternView.topAnchor),
            cellGuide.widthAnchor.constraint(equalTo: patternView.widthAnchor, multiplier: 0.5),
            cellGuide.heightAnchor.constraint(equalTo: patternView.heightAnchor, multiplier: 0.25),

            shareButton.widthAnchor.constraint(equalToConstant: 28),
            shareButton.heightAnchor.constraint(equalToConstant: 28),
            shareButton.centerXAnchor.constraint(equalTo: cellGuide.centerXAnchor),
            shareButton.centerYAnchor.constraint(equalTo: cellGuide.centerYAnchor, constant: -1),

            contentStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: patternView.leadingAnchor, constant: -14),
            contentStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 18),
            contentStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -18)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onShareTapped = nil
        onFieldTapped = nil
    }

    func configure(
        ownerName: String,
        shopName: String?,
        phone: String?,
        email: String?,
        address: String?,
        gstin: String?,
        website: String?
    ) {
        apply(shopLabel, value: shopName, placeholder: "Add shop name")
        apply(ownerLabel, value: ownerName, placeholder: "Add owner name")
        apply(contactPhoneLabel, value: phone, placeholder: "Add mobile number")
        apply(addressLabel, value: address, placeholder: "Add address")
        apply(gstinLabel, value: gstin.map { "GSTIN \($0)" }, placeholder: "Add GSTIN")
        apply(emailLabel, value: email, placeholder: "Add email")
        apply(websiteLabel, value: website, placeholder: "Add website")
    }

    func cardImageForShare() -> UIImage {
        shareButton.isHidden = true
        let placeholderLabels = fieldLabels.filter { $0.tag == 1 }
        placeholderLabels.forEach { $0.isHidden = true }

        let savedRadius = cardView.layer.cornerRadius
        cardView.layer.cornerRadius = 0
        cardView.clipsToBounds = true
        cardView.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: cardView.bounds, format: format)
        let image = renderer.image { ctx in
            BusinessCardPalette.lime.setFill()
            ctx.fill(cardView.bounds)
            cardView.layer.render(in: ctx.cgContext)
        }

        cardView.layer.cornerRadius = savedRadius
        placeholderLabels.forEach { $0.isHidden = false }
        shareButton.isHidden = false
        return image
    }

    private var fieldLabels: [UILabel] {
        [shopLabel, ownerLabel, contactPhoneLabel, addressLabel, gstinLabel, emailLabel, websiteLabel]
    }

    private func configureInfoLabel(_ label: UILabel, size: CGFloat, weight: UIFont.Weight, lines: Int) {
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = .white
        label.numberOfLines = lines
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        label.isUserInteractionEnabled = true
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)
    }

    private func apply(_ label: UILabel, value: String?, placeholder: String) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            label.text = placeholder
            label.textColor = UIColor.white.withAlphaComponent(0.55)
            label.tag = 1
        } else {
            label.text = trimmed
            label.textColor = .white
            label.tag = 0
        }
    }

    @objc private func tapShare() { onShareTapped?() }
    @objc private func tapShop() { onFieldTapped?(.shop) }
    @objc private func tapOwner() { onFieldTapped?(.owner) }
    @objc private func tapPhone() { onFieldTapped?(.phone) }
    @objc private func tapAddress() { onFieldTapped?(.address) }
    @objc private func tapGSTIN() { onFieldTapped?(.gstin) }
    @objc private func tapEmail() { onFieldTapped?(.email) }
    @objc private func tapWebsite() { onFieldTapped?(.website) }
}

enum BusinessCardPalette {
    static let lime = UIColor(named: "Lime Moss") ?? UIColor(red: 0.55, green: 0.72, blue: 0.20, alpha: 1)
    /// Lighter Lime Moss for the decorative checker pattern.
    static let limeLight: UIColor = {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        lime.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r + (1 - r) * 0.42, green: g + (1 - g) * 0.42, blue: b + (1 - b) * 0.42, alpha: 1)
    }()
}

private final class BusinessCardShellView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = BusinessCardPalette.lime
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        clipsToBounds = true
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { nil }
}

private final class BusinessCardPatternStrip: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ rect: CGRect) {
        let cols = 2
        let rows = 4
        let w = rect.width / CGFloat(cols)
        let h = rect.height / CGFloat(rows)
        let glyphs: [(CGContext) -> Void] = [drawDot, drawRing, drawCornerArcs, drawFloralX]

        for row in 0..<rows {
            for col in 0..<cols {
                let cell = CGRect(x: CGFloat(col) * w, y: CGFloat(row) * h, width: w, height: h)
                let isWhite = (row + col) % 2 == 0
                (isWhite ? UIColor.white : BusinessCardPalette.limeLight).setFill()
                UIBezierPath(rect: cell).fill()

                guard let ctx = UIGraphicsGetCurrentContext() else { continue }
                ctx.saveGState()
                let ink = isWhite ? BusinessCardPalette.limeLight : UIColor.white
                ink.setFill()
                ink.setStroke()
                ctx.translateBy(x: cell.minX, y: cell.minY)
                ctx.scaleBy(x: cell.width, y: cell.height)
                glyphs[(row * cols + col) % glyphs.count](ctx)
                ctx.restoreGState()
            }
        }
    }

    private func drawDot(_ ctx: CGContext) {
        ctx.setLineWidth(0)
        ctx.fillEllipse(in: CGRect(x: 0.38, y: 0.38, width: 0.24, height: 0.24))
    }

    private func drawRing(_ ctx: CGContext) {
        ctx.setLineWidth(0.07)
        ctx.strokeEllipse(in: CGRect(x: 0.18, y: 0.18, width: 0.64, height: 0.64))
    }

    private func drawCornerArcs(_ ctx: CGContext) {
        ctx.setLineWidth(0.055)
        ctx.setLineCap(.round)
        for i in 0..<3 {
            ctx.addArc(
                center: CGPoint(x: 0.08, y: 0.92),
                radius: 0.22 + CGFloat(i) * 0.22,
                startAngle: -.pi / 2,
                endAngle: 0,
                clockwise: false
            )
            ctx.strokePath()
        }
    }

    private func drawFloralX(_ ctx: CGContext) {
        ctx.setLineWidth(0.06)
        ctx.setLineCap(.round)
        let pairs: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: 0.18, y: 0.18), CGPoint(x: 0.38, y: 0.50), CGPoint(x: 0.18, y: 0.82)),
            (CGPoint(x: 0.82, y: 0.18), CGPoint(x: 0.62, y: 0.50), CGPoint(x: 0.82, y: 0.82)),
            (CGPoint(x: 0.18, y: 0.18), CGPoint(x: 0.50, y: 0.38), CGPoint(x: 0.82, y: 0.18)),
            (CGPoint(x: 0.18, y: 0.82), CGPoint(x: 0.50, y: 0.62), CGPoint(x: 0.82, y: 0.82))
        ]
        for (a, c, b) in pairs {
            ctx.move(to: a)
            ctx.addQuadCurve(to: b, control: c)
            ctx.strokePath()
        }
    }
}
