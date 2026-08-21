import UIKit

class CompleteProfileViewController: UIViewController, UITextFieldDelegate {

    var prefilledName: String?
    var prefilledShop: String?
    var prefilledPhone: String?
    var prefilledEmail: String?

    private let welcomeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Almost there"
        label.font = .boldSystemFont(ofSize: 28)
        label.textColor = .label
        return label
    }()

    private let detailLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Add your name, shop, and phone to finish setup"
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    private let personNameField = UITextField()
    private let shopNameField = UITextField()
    private let phoneField = UITextField()
    private let countryCodeButton = UIButton(type: .system)
    private let continueButton = UIButton(type: .system)

    private var selectedCountryCode = "+91"
    private var selectedFlag = "🇮🇳"
    private var didPrefillFromRemote = false

    private let countryCodes: [(flag: String, code: String, name: String)] = [
        ("🇮🇳", "+91", "India"),
        ("🇺🇸", "+1", "USA"),
        ("🇬🇧", "+44", "UK"),
        ("🇦🇪", "+971", "UAE"),
        ("🇨🇦", "+1", "Canada"),
        ("🇦🇺", "+61", "Australia"),
        ("🇩🇪", "+49", "Germany"),
        ("🇫🇷", "+33", "France"),
        ("🇯🇵", "+81", "Japan"),
        ("🇸🇬", "+65", "Singapore")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Complete Profile"
        view.backgroundColor = .systemBackground
        navigationItem.hidesBackButton = true
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false

        buildLayout()
        styleUI()
        configureFields()
        applyPrefills()
        updateContinueState()
        fetchRemoteProfileIfNeeded()
    }

    private func buildLayout() {
        styleTextField(personNameField, placeholder: "Your Full Name")
        styleTextField(shopNameField, placeholder: "Your Shop / Business Name")
        styleTextField(phoneField, placeholder: "Phone Number")

        countryCodeButton.translatesAutoresizingMaskIntoConstraints = false
        countryCodeButton.setTitle("🇮🇳 +91 ▾", for: .normal)
        countryCodeButton.setTitleColor(.label, for: .normal)
        countryCodeButton.addTarget(self, action: #selector(countryCodeTapped), for: .touchUpInside)

        let phoneStack = UIStackView(arrangedSubviews: [countryCodeButton, phoneField])
        phoneStack.translatesAutoresizingMaskIntoConstraints = false
        phoneStack.axis = .horizontal
        phoneStack.spacing = 8

        var buttonConfig = UIButton.Configuration.filled()
        buttonConfig.title = "Continue"
        buttonConfig.baseBackgroundColor = UIColor(named: "Lime Moss") ?? .black
        buttonConfig.baseForegroundColor = .white
        buttonConfig.cornerStyle = .fixed
        continueButton.configuration = buttonConfig
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)

        view.addSubview(welcomeLabel)
        view.addSubview(detailLabel)
        view.addSubview(personNameField)
        view.addSubview(shopNameField)
        view.addSubview(phoneStack)
        view.addSubview(continueButton)

        NSLayoutConstraint.activate([
            welcomeLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            welcomeLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            welcomeLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),

            detailLabel.topAnchor.constraint(equalTo: welcomeLabel.bottomAnchor, constant: 8),
            detailLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            detailLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),

            personNameField.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 32),
            personNameField.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            personNameField.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            personNameField.heightAnchor.constraint(equalToConstant: 50),

            shopNameField.topAnchor.constraint(equalTo: personNameField.bottomAnchor, constant: 16),
            shopNameField.leadingAnchor.constraint(equalTo: personNameField.leadingAnchor),
            shopNameField.trailingAnchor.constraint(equalTo: personNameField.trailingAnchor),
            shopNameField.heightAnchor.constraint(equalToConstant: 50),

            phoneStack.topAnchor.constraint(equalTo: shopNameField.bottomAnchor, constant: 16),
            phoneStack.leadingAnchor.constraint(equalTo: personNameField.leadingAnchor),
            phoneStack.trailingAnchor.constraint(equalTo: personNameField.trailingAnchor),
            phoneStack.heightAnchor.constraint(equalToConstant: 50),

            countryCodeButton.widthAnchor.constraint(equalToConstant: 100),

            continueButton.topAnchor.constraint(equalTo: phoneStack.bottomAnchor, constant: 40),
            continueButton.leadingAnchor.constraint(equalTo: personNameField.leadingAnchor),
            continueButton.trailingAnchor.constraint(equalTo: personNameField.trailingAnchor),
            continueButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func styleTextField(_ field: UITextField, placeholder: String) {
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 16)
        field.layer.cornerRadius = 12
        field.layer.borderWidth = 1
        field.layer.borderColor = UIColor.systemGray4.cgColor
        field.clipsToBounds = true
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 0))
        field.leftViewMode = .always
    }

    private func styleUI() {
        countryCodeButton.layer.cornerRadius = 12
        countryCodeButton.layer.borderWidth = 1
        countryCodeButton.layer.borderColor = UIColor.systemGray4.cgColor
        countryCodeButton.clipsToBounds = true

        continueButton.layer.cornerRadius = 14
        continueButton.clipsToBounds = true
    }

    private func configureFields() {
        personNameField.returnKeyType = .next
        personNameField.autocapitalizationType = .words
        personNameField.delegate = self
        personNameField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        shopNameField.returnKeyType = .next
        shopNameField.autocapitalizationType = .words
        shopNameField.delegate = self
        shopNameField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        phoneField.keyboardType = .numberPad
        phoneField.delegate = self
        phoneField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func applyPrefills() {
        if let name = cleaned(prefilledName) {
            personNameField.text = name
        }
        if let shop = cleaned(prefilledShop), shop.lowercased() != "my shop" {
            shopNameField.text = shop
        }
        applyPhonePrefill(prefilledPhone)
        updateContinueState()
    }

    private func applyPhonePrefill(_ rawPhone: String?) {
        guard let raw = cleaned(rawPhone) else { return }
        let digitsOnly = raw.filter { $0.isNumber }

        if let match = countryCodes.first(where: { raw.hasPrefix($0.code) }) {
            selectedCountryCode = match.code
            selectedFlag = match.flag
            countryCodeButton.setTitle("\(match.flag) \(match.code) ▾", for: .normal)
            let local = String(digitsOnly.dropFirst(match.code.filter { $0.isNumber }.count))
            phoneField.text = String(local.prefix(10))
            return
        }

        phoneField.text = String(digitsOnly.suffix(10))
    }

    private func fetchRemoteProfileIfNeeded() {
        guard AuthManager.shared.isConfigured, !didPrefillFromRemote else { return }

        AuthManager.shared.fetchUserProfile { [weak self] profile in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.didPrefillFromRemote = true

                if let profile, AuthNavigationHelper.isRemoteProfileComplete(profile) {
                    AuthNavigationHelper.applyRemoteProfile(profile)
                    AuthNavigationHelper.continueAfterAccountReady()
                    return
                }

                if self.cleaned(self.personNameField.text) == nil,
                   let name = profile?["owner_name"] as? String {
                    self.personNameField.text = name
                }
                if self.cleaned(self.shopNameField.text) == nil,
                   let shop = profile?["shop_name"] as? String {
                    self.shopNameField.text = shop
                }
                if self.cleaned(self.phoneField.text) == nil {
                    self.applyPhonePrefill(profile?["phone"] as? String)
                }
                self.updateContinueState()
            }
        }
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isValidPhone(_ phone: String) -> Bool {
        AuthNavigationHelper.isValidPhone(phone, countryCode: selectedCountryCode)
    }

    private func allFieldsValid() -> Bool {
        AuthNavigationHelper.isValidPersonName(personNameField.text ?? "")
            && AuthNavigationHelper.isValidShopName(shopNameField.text ?? "")
            && isValidPhone(phoneField.text ?? "")
    }

    private func updateContinueState() {
        let valid = allFieldsValid()
        continueButton.isEnabled = valid
        UIView.animate(withDuration: 0.2) {
            self.continueButton.alpha = valid ? 1.0 : 0.5
        }
    }

    @objc private func textFieldDidChange() {
        updateContinueState()
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func countryCodeTapped() {
        let alert = UIAlertController(title: "Select Country Code", message: nil, preferredStyle: .actionSheet)
        for cc in countryCodes {
            alert.addAction(UIAlertAction(title: "\(cc.flag) \(cc.name) (\(cc.code))", style: .default) { [weak self] _ in
                self?.selectedFlag = cc.flag
                self?.selectedCountryCode = cc.code
                self?.countryCodeButton.setTitle("\(cc.flag) \(cc.code) ▾", for: .normal)
                self?.updateContinueState()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func continueTapped() {
        var errors: [String] = []
        if !AuthNavigationHelper.isValidPersonName(personNameField.text ?? "") {
            errors.append("• Enter a valid name (at least 2 letters)")
        }
        if !AuthNavigationHelper.isValidShopName(shopNameField.text ?? "") {
            errors.append("• Enter a valid shop name (letters or numbers, at least 2 characters)")
        }
        if !isValidPhone(phoneField.text ?? "") {
            errors.append("• Enter a valid phone number")
        }

        if !errors.isEmpty {
            let alert = UIAlertController(title: "Invalid Input", message: errors.joined(separator: "\n"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let trimmedName = personNameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedShop = shopNameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let phone = phoneField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayPhone = "\(selectedCountryCode) \(phone)"

        setLoading(true)
        AuthNavigationHelper.saveLocalProfile(name: trimmedName, shopName: trimmedShop, phone: displayPhone)
        AuthManager.shared.updateUserProfile(
            name: trimmedName,
            shopName: trimmedShop,
            phone: displayPhone,
            email: prefilledEmail ?? AuthManager.shared.appleEmail
        ) { [weak self] error in
            DispatchQueue.main.async {
                self?.setLoading(false)
                if let error {
                    let alert = UIAlertController(
                        title: "Saved on this device",
                        message: "Cloud profile sync failed: \(error.localizedDescription)",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in
                        AuthNavigationHelper.continueAfterAccountReady()
                    })
                    self?.present(alert, animated: true)
                    return
                }
                AuthNavigationHelper.continueAfterAccountReady()
            }
        }
    }

    private func setLoading(_ loading: Bool) {
        continueButton.isEnabled = !loading
        if var config = continueButton.configuration {
            config.title = loading ? "Saving..." : "Continue"
            continueButton.configuration = config
        }
        continueButton.alpha = loading ? 0.6 : (allFieldsValid() ? 1.0 : 0.5)
        personNameField.isEnabled = !loading
        shopNameField.isEnabled = !loading
        phoneField.isEnabled = !loading
        countryCodeButton.isEnabled = !loading
    }

    func textField(_ textField: UITextField,
                   shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        if textField == phoneField {
            let allowed = CharacterSet.decimalDigits
            if !allowed.isSuperset(of: CharacterSet(charactersIn: string)) && !string.isEmpty {
                return false
            }
            let current = textField.text ?? ""
            let newLen = current.count + string.count - range.length
            return newLen <= (selectedCountryCode == "+91" ? 10 : 15)
        }

        if textField == personNameField {
            let allowed = CharacterSet.letters.union(.whitespaces)
            return allowed.isSuperset(of: CharacterSet(charactersIn: string)) || string.isEmpty
        }

        if textField == shopNameField {
            let allowed = CharacterSet.letters.union(.decimalDigits).union(.whitespaces)
                .union(CharacterSet(charactersIn: "&-.'"))
            return allowed.isSuperset(of: CharacterSet(charactersIn: string)) || string.isEmpty
        }

        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        switch textField {
        case personNameField: shopNameField.becomeFirstResponder()
        case shopNameField:   phoneField.becomeFirstResponder()
        default:              textField.resignFirstResponder()
        }
        return true
    }
}
