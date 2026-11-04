import UIKit

enum BusinessCardField {
    case logo
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
    private let dividerView = UIView()

    // Left Column: Logo & Shop Name (top) + App Icon & Powered by B-easy (bottom)
    private let leftContainerView = UIView()
    private let topBrandingStack = UIStackView()
    private let logoContainerView = UIView()
    private let logoImageView = UIImageView()
    private let shopLabel = UILabel()

    private let poweredByStack = UIStackView()
    private let appIconImageView = UIImageView()
    private let brandTitleLabel = UILabel()
    private let poweredByLabel = UILabel()

    // Right Column: Contact Details with Icons
    private let rightContainerView = UIView()
    private let contactStack = UIStackView()
    private let contactPhoneLabel = UILabel()
    private let addressLabel = UILabel()
    private let emailLabel = UILabel()
    private let websiteLabel = UILabel()
    private let gstinLabel = UILabel()

    private var phoneRowView: UIView?
    private var addressRowView: UIView?
    private var emailRowView: UIView?
    private var websiteRowView: UIView?
    private var gstinRowView: UIView?

    // Share Button
    private let shareButton = UIButton(type: .system)

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
            $0?.constraints.forEach { $0.isActive = false }
            $0?.isHidden = true
            $0?.removeFromSuperview()
        }

        setupSubviews()
        setupConstraints()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onShareTapped = nil
        onFieldTapped = nil
    }

    private func setupSubviews() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        dividerView.translatesAutoresizingMaskIntoConstraints = false
        dividerView.backgroundColor = UIColor.white.withAlphaComponent(0.35)
        cardView.addSubview(dividerView)

        leftContainerView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(leftContainerView)

        rightContainerView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(rightContainerView)

        // Logo Container (frosted glass look)
        logoContainerView.translatesAutoresizingMaskIntoConstraints = false
        logoContainerView.backgroundColor = UIColor.white.withAlphaComponent(0.24)
        logoContainerView.layer.cornerRadius = 15
        logoContainerView.layer.cornerCurve = .continuous
        logoContainerView.layer.borderWidth = 1
        logoContainerView.layer.borderColor = UIColor.white.withAlphaComponent(0.38).cgColor
        logoContainerView.clipsToBounds = true
        logoContainerView.isUserInteractionEnabled = true
        logoContainerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapLogo)))

        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.contentMode = .center
        logoImageView.clipsToBounds = true
        logoImageView.tintColor = .white
        logoContainerView.addSubview(logoImageView)

        // Shop Name Label
        configureInfoLabel(shopLabel, size: 19, weight: .bold, lines: 2, alignment: .left)
        shopLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapShop)))

        topBrandingStack.translatesAutoresizingMaskIntoConstraints = false
        topBrandingStack.axis = .horizontal
        topBrandingStack.alignment = .center
        topBrandingStack.spacing = 10
        topBrandingStack.addArrangedSubview(logoContainerView)
        topBrandingStack.addArrangedSubview(shopLabel)
        leftContainerView.addSubview(topBrandingStack)

        // Bottom-left: App icon + "Powered by" on top, "B-easy" under it
        appIconImageView.translatesAutoresizingMaskIntoConstraints = false
        appIconImageView.image = UIImage(named: "BEasyAppIcon") ?? UIImage(systemName: "app.fill")
        appIconImageView.contentMode = .scaleAspectFill
        appIconImageView.layer.cornerRadius = 6.5
        appIconImageView.layer.cornerCurve = .continuous
        appIconImageView.clipsToBounds = true

        poweredByLabel.font = .systemFont(ofSize: 9.5, weight: .medium)
        poweredByLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        poweredByLabel.text = "Powered by"

        brandTitleLabel.font = .systemFont(ofSize: 13.5, weight: .bold)
        brandTitleLabel.textColor = .white
        brandTitleLabel.text = "B-easy"

        let brandTextStack = UIStackView(arrangedSubviews: [poweredByLabel, brandTitleLabel])
        brandTextStack.axis = .vertical
        brandTextStack.alignment = .leading
        brandTextStack.spacing = 0.5

        poweredByStack.translatesAutoresizingMaskIntoConstraints = false
        poweredByStack.axis = .horizontal
        poweredByStack.alignment = .center
        poweredByStack.spacing = 6.5
        poweredByStack.addArrangedSubview(appIconImageView)
        poweredByStack.addArrangedSubview(brandTextStack)
        leftContainerView.addSubview(poweredByStack)

        // Right side: Contact Stack with Icons
        configureInfoLabel(contactPhoneLabel, size: 12.5, weight: .medium, lines: 1)
        configureInfoLabel(addressLabel, size: 11, weight: .regular, lines: 2)
        configureInfoLabel(emailLabel, size: 11.5, weight: .regular, lines: 1)
        configureInfoLabel(websiteLabel, size: 11.5, weight: .regular, lines: 1)
        configureInfoLabel(gstinLabel, size: 11.5, weight: .medium, lines: 1)

        let phoneRow = makeContactRow(iconName: "phone.fill", label: contactPhoneLabel, action: #selector(tapPhone))
        let addressRow = makeContactRow(iconName: "mappin.and.ellipse", label: addressLabel, action: #selector(tapAddress))
        let emailRow = makeContactRow(iconName: "envelope.fill", label: emailLabel, action: #selector(tapEmail))
        let websiteRow = makeContactRow(iconName: "globe", label: websiteLabel, action: #selector(tapWebsite))
        let gstinRow = makeContactRow(iconName: "building.2.fill", label: gstinLabel, action: #selector(tapGSTIN))

        phoneRowView = phoneRow
        addressRowView = addressRow
        emailRowView = emailRow
        websiteRowView = websiteRow
        gstinRowView = gstinRow

        contactStack.translatesAutoresizingMaskIntoConstraints = false
        contactStack.axis = .vertical
        contactStack.alignment = .fill
        contactStack.spacing = 7
        contactStack.addArrangedSubview(phoneRow)
        contactStack.addArrangedSubview(addressRow)
        contactStack.addArrangedSubview(emailRow)
        contactStack.addArrangedSubview(websiteRow)
        contactStack.addArrangedSubview(gstinRow)
        rightContainerView.addSubview(contactStack)

        // Share button in top-right corner
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        let shareConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        shareButton.setImage(UIImage(systemName: "square.and.arrow.up", withConfiguration: shareConfig), for: .normal)
        shareButton.tintColor = .white
        shareButton.setTitle(nil, for: .normal)
        shareButton.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        shareButton.layer.cornerRadius = 13
        shareButton.clipsToBounds = true
        shareButton.accessibilityLabel = "Share business card"
        shareButton.addTarget(self, action: #selector(tapShare), for: .touchUpInside)
        cardView.addSubview(shareButton)
    }

    private func makeContactRow(iconName: String, label: UILabel, action: Selector) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isUserInteractionEnabled = true
        row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: action))

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 12.5, weight: .medium)
        iconView.image = UIImage(systemName: iconName, withConfiguration: symbolConfig)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        label.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(iconView)
        row.addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            iconView.topAnchor.constraint(equalTo: row.topAnchor, constant: 1),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            label.topAnchor.constraint(equalTo: row.topAnchor),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            row.bottomAnchor.constraint(greaterThanOrEqualTo: iconView.bottomAnchor)
        ])

        return row
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Card shell
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            cardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 176),

            // Divider line
            dividerView.widthAnchor.constraint(equalToConstant: 1),
            dividerView.centerXAnchor.constraint(equalTo: cardView.centerXAnchor, constant: -10),
            dividerView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 20),
            dividerView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -20),

            // Left container
            leftContainerView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            leftContainerView.trailingAnchor.constraint(equalTo: dividerView.leadingAnchor, constant: -12),
            leftContainerView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            leftContainerView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),

            // Logo container
            logoContainerView.widthAnchor.constraint(equalToConstant: 52),
            logoContainerView.heightAnchor.constraint(equalToConstant: 52),
            logoImageView.leadingAnchor.constraint(equalTo: logoContainerView.leadingAnchor),
            logoImageView.trailingAnchor.constraint(equalTo: logoContainerView.trailingAnchor),
            logoImageView.topAnchor.constraint(equalTo: logoContainerView.topAnchor),
            logoImageView.bottomAnchor.constraint(equalTo: logoContainerView.bottomAnchor),

            // Top branding stack (logo + shop name)
            topBrandingStack.topAnchor.constraint(equalTo: leftContainerView.topAnchor),
            topBrandingStack.leadingAnchor.constraint(equalTo: leftContainerView.leadingAnchor),
            topBrandingStack.trailingAnchor.constraint(equalTo: leftContainerView.trailingAnchor),

            // Powered by stack
            appIconImageView.widthAnchor.constraint(equalToConstant: 26),
            appIconImageView.heightAnchor.constraint(equalToConstant: 26),

            poweredByStack.leadingAnchor.constraint(equalTo: leftContainerView.leadingAnchor),
            poweredByStack.trailingAnchor.constraint(lessThanOrEqualTo: leftContainerView.trailingAnchor),
            poweredByStack.bottomAnchor.constraint(equalTo: leftContainerView.bottomAnchor),
            poweredByStack.topAnchor.constraint(greaterThanOrEqualTo: topBrandingStack.bottomAnchor, constant: 14),

            // Right container
            rightContainerView.leadingAnchor.constraint(equalTo: dividerView.trailingAnchor, constant: 12),
            rightContainerView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            rightContainerView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            rightContainerView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),

            // Contact stack centered vertically on the right
            contactStack.leadingAnchor.constraint(equalTo: rightContainerView.leadingAnchor),
            contactStack.trailingAnchor.constraint(equalTo: rightContainerView.trailingAnchor),
            contactStack.centerYAnchor.constraint(equalTo: rightContainerView.centerYAnchor),
            contactStack.topAnchor.constraint(greaterThanOrEqualTo: rightContainerView.topAnchor),
            contactStack.bottomAnchor.constraint(lessThanOrEqualTo: rightContainerView.bottomAnchor),

            // Share button (top-right corner)
            shareButton.widthAnchor.constraint(equalToConstant: 26),
            shareButton.heightAnchor.constraint(equalToConstant: 26),
            shareButton.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            shareButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -10)
        ])
    }

    func configure(
        ownerName: String,
        shopName: String?,
        phone: String?,
        email: String?,
        address: String?,
        gstin: String?,
        website: String?,
        logoImage: UIImage? = nil
    ) {
        if let logoImage {
            logoImageView.image = logoImage
            logoImageView.contentMode = .scaleAspectFill
            logoImageView.tintColor = nil
        } else {
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 26, weight: .regular)
            logoImageView.image = UIImage(systemName: "storefront.fill", withConfiguration: symbolConfig)
            logoImageView.contentMode = .center
            logoImageView.tintColor = .white
        }

        let displayShop = (shopName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? shopName
            : (!ownerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ownerName : nil)

        apply(shopLabel, value: displayShop, placeholder: "Add shop name")
        apply(contactPhoneLabel, value: phone, placeholder: "Add mobile")
        apply(addressLabel, value: address, placeholder: "Add address")
        apply(emailLabel, value: email, placeholder: "Add email")
        apply(websiteLabel, value: website, placeholder: "Add website")
        apply(gstinLabel, value: gstin.map { "GSTIN \($0)" }, placeholder: "Add GSTIN")
    }

    func cardImageForShare() -> UIImage {
        shareButton.isHidden = true

        let rows: [(UIView?, UILabel)] = [
            (phoneRowView, contactPhoneLabel),
            (addressRowView, addressLabel),
            (emailRowView, emailLabel),
            (websiteRowView, websiteLabel),
            (gstinRowView, gstinLabel)
        ]

        var hiddenRows: [UIView] = []
        for (row, label) in rows {
            if label.tag == 1, let r = row {
                r.isHidden = true
                hiddenRows.append(r)
            }
        }

        let savedRadius = cardView.layer.cornerRadius
        cardView.layer.cornerRadius = 0
        cardView.clipsToBounds = true
        cardView.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: cardView.bounds, format: format)
        let image = renderer.image { ctx in
            cardView.layer.render(in: ctx.cgContext)
        }

        cardView.layer.cornerRadius = savedRadius
        hiddenRows.forEach { $0.isHidden = false }
        shareButton.isHidden = false
        cardView.layoutIfNeeded()

        return image
    }

    private func configureInfoLabel(
        _ label: UILabel,
        size: CGFloat,
        weight: UIFont.Weight,
        lines: Int,
        alignment: NSTextAlignment = .left
    ) {
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = .white
        label.textAlignment = alignment
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
            label.textColor = UIColor.white.withAlphaComponent(0.60)
            label.tag = 1
        } else {
            label.text = trimmed
            label.textColor = .white
            label.tag = 0
        }
    }

    @objc private func tapLogo() { onFieldTapped?(.logo) }
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
    static let lime = UIColor(named: "Lime Moss") ?? UIColor(red: 0.412, green: 0.561, blue: 0.0, alpha: 1)
}

private final class BusinessCardShellView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = BusinessCardPalette.lime
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        clipsToBounds = true
        isUserInteractionEnabled = true
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // Base color: Lime Moss directly from app theme & dashboard revenue tile
        let baseLime = BusinessCardPalette.lime
        var r: CGFloat = 0.412, g: CGFloat = 0.561, b: CGFloat = 0.0, a: CGFloat = 1.0
        baseLime.getRed(&r, green: &g, blue: &b, alpha: &a)

        // 1. Vibrant app-theme gradient: subtle highlight at top-left, true Lime Moss across body, slightly deeper at bottom-right
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let topColor = UIColor(
            red: min(1.0, r + (1.0 - r) * 0.14),
            green: min(1.0, g + (1.0 - g) * 0.14),
            blue: min(1.0, b + 0.04),
            alpha: 1.0
        ).cgColor
        let midColor = UIColor(red: r, green: g, blue: b, alpha: 1.0).cgColor
        let botColor = UIColor(
            red: max(0.0, r * 0.90),
            green: max(0.0, g * 0.90),
            blue: max(0.0, b * 0.90),
            alpha: 1.0
        ).cgColor

        let colors = [topColor, midColor, botColor] as CFArray
        let locations: [CGFloat] = [0.0, 0.45, 1.0]

        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: rect.width, y: rect.height),
                options: []
            )
        }

        // 2. First organic curved wave (soft subtle darkening, keeping the green vibrant and true to Lime Moss)
        let path1 = UIBezierPath()
        path1.move(to: CGPoint(x: 0, y: rect.height * 0.52))
        path1.addCurve(
            to: CGPoint(x: rect.width * 0.55, y: rect.height * 0.78),
            controlPoint1: CGPoint(x: rect.width * 0.15, y: rect.height * 0.68),
            controlPoint2: CGPoint(x: rect.width * 0.35, y: rect.height * 0.80)
        )
        path1.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.68),
            controlPoint1: CGPoint(x: rect.width * 0.72, y: rect.height * 0.76),
            controlPoint2: CGPoint(x: rect.width * 0.88, y: rect.height * 0.70)
        )
        path1.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path1.addLine(to: CGPoint(x: 0, y: rect.height))
        path1.close()

        ctx.saveGState()
        UIColor.black.withAlphaComponent(0.06).setFill()
        path1.fill()
        ctx.restoreGState()

        // 3. Second deeper wave swoosh at bottom-left
        let path2 = UIBezierPath()
        path2.move(to: CGPoint(x: 0, y: rect.height * 0.68))
        path2.addCurve(
            to: CGPoint(x: rect.width * 0.45, y: rect.height * 0.90),
            controlPoint1: CGPoint(x: rect.width * 0.12, y: rect.height * 0.82),
            controlPoint2: CGPoint(x: rect.width * 0.28, y: rect.height * 0.92)
        )
        path2.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.82),
            controlPoint1: CGPoint(x: rect.width * 0.65, y: rect.height * 0.88),
            controlPoint2: CGPoint(x: rect.width * 0.85, y: rect.height * 0.84)
        )
        path2.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path2.addLine(to: CGPoint(x: 0, y: rect.height))
        path2.close()

        ctx.saveGState()
        UIColor.black.withAlphaComponent(0.08).setFill()
        path2.fill()
        ctx.restoreGState()

        // 4. Subtle top wave glow highlight
        let highlightPath = UIBezierPath()
        highlightPath.move(to: CGPoint(x: 0, y: rect.height * 0.52))
        highlightPath.addCurve(
            to: CGPoint(x: rect.width * 0.55, y: rect.height * 0.78),
            controlPoint1: CGPoint(x: rect.width * 0.15, y: rect.height * 0.68),
            controlPoint2: CGPoint(x: rect.width * 0.35, y: rect.height * 0.80)
        )
        highlightPath.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.68),
            controlPoint1: CGPoint(x: rect.width * 0.72, y: rect.height * 0.76),
            controlPoint2: CGPoint(x: rect.width * 0.88, y: rect.height * 0.70)
        )
        ctx.saveGState()
        UIColor.white.withAlphaComponent(0.12).setStroke()
        highlightPath.lineWidth = 1.0
        highlightPath.stroke()
        ctx.restoreGState()
    }
}
