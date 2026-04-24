import UIKit

class SignupViewController: UIViewController, UITextFieldDelegate {

    // MARK: - IBOutlets (connect these in Storyboard)

    @IBOutlet weak var welcomeLabel: UILabel!
    @IBOutlet weak var detailLabel: UILabel!
    @IBOutlet weak var personNameField: UITextField!
    @IBOutlet weak var shopNameField: UITextField!
    @IBOutlet weak var countryCodeButton: UIButton!
    @IBOutlet weak var phoneField: UITextField!
    @IBOutlet weak var sendCodeButton: UIButton!

    // MARK: - State

    private var selectedCountryCode = "+91"
    private var selectedFlag = "🇮🇳"

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

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Sign Up"
        styleUI()
        configureFields()
        configureCountryCodeButton()
        updateSendCodeState()
    }

    // MARK: - Styling (only things that can't be done in Storyboard)

    private func styleUI() {
        // Rounded corners for text fields
        for field in [personNameField, shopNameField, phoneField] {
            field?.layer.cornerRadius = 12
            field?.layer.borderWidth = 1
            field?.layer.borderColor = UIColor.systemGray4.cgColor
            field?.clipsToBounds = true
            field?.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 0))
            field?.leftViewMode = .always
        }

        // Country code button styling
        countryCodeButton.layer.cornerRadius = 12
        countryCodeButton.layer.borderWidth = 1
        countryCodeButton.layer.borderColor = UIColor.systemGray4.cgColor
        countryCodeButton.clipsToBounds = true

        // Send code button styling
        sendCodeButton.layer.cornerRadius = 14
        sendCodeButton.clipsToBounds = true
    }

    // MARK: - Configuration

    private func configureFields() {
        personNameField.placeholder = "Your Full Name"
        personNameField.returnKeyType = .next
        personNameField.autocapitalizationType = .words
        personNameField.delegate = self
        personNameField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        shopNameField.placeholder = "Your Shop / Business Name"
        shopNameField.returnKeyType = .next
        shopNameField.autocapitalizationType = .words
        shopNameField.delegate = self
        shopNameField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        phoneField.placeholder = "Phone Number"
        phoneField.keyboardType = .numberPad
        phoneField.delegate = self
        phoneField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func configureCountryCodeButton() {
        countryCodeButton.setTitle("🇮🇳 +91 ▾", for: .normal)
        countryCodeButton.setTitleColor(.label, for: .normal)
        countryCodeButton.addTarget(self, action: #selector(countryCodeTapped), for: .touchUpInside)
    }

    // MARK: - Validation

    private func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }
        return trimmed.allSatisfy { $0.isLetter || $0 == " " }
    }

    private func isValidPhone(_ phone: String) -> Bool {
        let digits = phone.filter { $0.isNumber }
        return digits.count == 10
    }

    private func allFieldsValid() -> Bool {
        return isValidName(personNameField.text ?? "") &&
               isValidName(shopNameField.text ?? "") &&
               isValidPhone(phoneField.text ?? "")
    }

    private func updateSendCodeState() {
        let valid = allFieldsValid()
        sendCodeButton.isEnabled = valid
        UIView.animate(withDuration: 0.2) {
            self.sendCodeButton.alpha = valid ? 1.0 : 0.5
        }
    }

    // MARK: - Actions

    @objc private func textFieldDidChange() {
        updateSendCodeState()
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
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @IBAction func sendCodeTapped(_ sender: UIButton) {
        var errors: [String] = []
        if !isValidName(personNameField.text ?? "") {
            errors.append("• Enter a valid name (at least 2 letters)")
        }
        if !isValidName(shopNameField.text ?? "") {
            errors.append("• Enter a valid shop name (at least 2 letters)")
        }
        if !isValidPhone(phoneField.text ?? "") {
            errors.append("• Enter a valid 10-digit phone number")
        }

        if !errors.isEmpty {
            let alert = UIAlertController(title: "Invalid Input", message: errors.joined(separator: "\n"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let trimmedName = personNameField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedShop = shopNameField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = phoneField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fullPhone = "\(selectedCountryCode)\(phone)"
        let displayPhone = "\(selectedCountryCode) \(phone)"

        // Save user info to local settings
        if var settings = try? AppDataModel.shared.dataModel.db.getSettings() {
            settings.ownerName = trimmedName
            settings.profileName = trimmedName
            if let trimmedShop, !trimmedShop.isEmpty {
                settings.businessName = trimmedShop
            }
            settings.businessPhone = displayPhone
            try? AppDataModel.shared.dataModel.db.updateSettings(settings)
        }

        // If Supabase is configured, send OTP via AuthManager
        if AuthManager.shared.isConfigured {
            setLoading(true)
            AuthManager.shared.sendOTP(phone: fullPhone) { [weak self] result in
                guard let self = self else { return }
                self.setLoading(false)
                switch result {
                case .success:
                    self.performSegue(withIdentifier: "goToOTP", sender: self)
                case .failure(let error):
                    let alert = UIAlertController(
                        title: "Could Not Send Code",
                        message: error.localizedDescription,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
        } else {
            // Supabase not configured — go straight to OTP (demo/dev mode)
            performSegue(withIdentifier: "goToOTP", sender: self)
        }
    }

    private func setLoading(_ loading: Bool) {
        sendCodeButton.isEnabled = !loading
        sendCodeButton.setTitle(loading ? "Sending..." : "Send Code", for: .normal)
        sendCodeButton.alpha = loading ? 0.6 : 1.0
        personNameField.isEnabled = !loading
        shopNameField.isEnabled = !loading
        phoneField.isEnabled = !loading
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "goToOTP" {
            let otpVC = segue.destination as! OTPViewController
            otpVC.phoneNumber = "\(selectedCountryCode) \(phoneField.text ?? "")"
        }
    }

    // MARK: - UITextFieldDelegate

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
            return newLen <= 10
        }

        if textField == personNameField || textField == shopNameField {
            let allowed = CharacterSet.letters.union(.whitespaces)
            return allowed.isSuperset(of: CharacterSet(charactersIn: string)) || string.isEmpty
        }

        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        switch textField {
        case personNameField: shopNameField.becomeFirstResponder()
        case shopNameField:   phoneField.becomeFirstResponder()
        case phoneField:      phoneField.resignFirstResponder()
        default:              textField.resignFirstResponder()
        }
        return true
    }
}
