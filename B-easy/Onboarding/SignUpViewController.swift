import UIKit
import AuthenticationServices

class SignupViewController: UIViewController, UITextFieldDelegate {



    @IBOutlet weak var welcomeLabel: UILabel!
    @IBOutlet weak var detailLabel: UILabel!
    @IBOutlet weak var personNameField: UITextField!
    @IBOutlet weak var shopNameField: UITextField!
    @IBOutlet weak var countryCodeButton: UIButton!
    @IBOutlet weak var phoneField: UITextField!
    @IBOutlet weak var sendCodeButton: UIButton!



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


    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Sign Up"
        styleUI()
        configureFields()
        configureCountryCodeButton()
        updateSendCodeState()
        configureAppleSignIn()
    }


    private func styleUI() {

        for field in [personNameField, shopNameField, phoneField] {
            field?.layer.cornerRadius = 12
            field?.layer.borderWidth = 1
            field?.layer.borderColor = UIColor.systemGray4.cgColor
            field?.clipsToBounds = true
            field?.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 0))
            field?.leftViewMode = .always
        }


        countryCodeButton.layer.cornerRadius = 12
        countryCodeButton.layer.borderWidth = 1
        countryCodeButton.layer.borderColor = UIColor.systemGray4.cgColor
        countryCodeButton.clipsToBounds = true


        sendCodeButton.layer.cornerRadius = 14
        sendCodeButton.clipsToBounds = true
        sendCodeButton.backgroundColor = .black
        sendCodeButton.setTitleColor(.white, for: .normal)
        sendCodeButton.setTitleColor(.lightGray, for: .disabled)
    }



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
        AuthNavigationHelper.isValidPersonName(name)
    }

    private func isValidShopName(_ name: String) -> Bool {
        AuthNavigationHelper.isValidShopName(name)
    }

    private func isValidPhone(_ phone: String) -> Bool {
        AuthNavigationHelper.isValidPhone(phone, countryCode: selectedCountryCode)
    }

    private func allFieldsValid() -> Bool {
        return isValidName(personNameField.text ?? "") &&
               isValidShopName(shopNameField.text ?? "") &&
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
        if !isValidShopName(shopNameField.text ?? "") {
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

        let trimmedName = personNameField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedShop = shopNameField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = phoneField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fullPhone = "\(selectedCountryCode)\(phone)"
        let displayPhone = "\(selectedCountryCode) \(phone)"


        if var settings = try? AppDataModel.shared.dataModel.db.getSettings() {
            settings.ownerName = trimmedName
            settings.profileName = trimmedName
            if let trimmedShop, !trimmedShop.isEmpty {
                settings.businessName = trimmedShop
            }
            settings.businessPhone = displayPhone
            try? AppDataModel.shared.dataModel.db.updateSettings(settings)
        }


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

    // MARK: - Apple Sign In
    
    private let appleSignInButton = ASAuthorizationAppleIDButton(authorizationButtonType: .signUp, authorizationButtonStyle: .black)
    
    private func configureAppleSignIn() {
        appleSignInButton.translatesAutoresizingMaskIntoConstraints = false
        appleSignInButton.addTarget(self, action: #selector(handleAppleSignIn), for: .touchUpInside)
        appleSignInButton.cornerRadius = 14
        view.addSubview(appleSignInButton)
        
        NSLayoutConstraint.activate([
            appleSignInButton.topAnchor.constraint(equalTo: sendCodeButton.bottomAnchor, constant: 20),
            appleSignInButton.leadingAnchor.constraint(equalTo: sendCodeButton.leadingAnchor),
            appleSignInButton.trailingAnchor.constraint(equalTo: sendCodeButton.trailingAnchor),
            appleSignInButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    @objc private func handleAppleSignIn() {
        AppleSignInHelper.shared.startSignIn(presentationAnchor: view.window) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    self?.setLoading(true)
                    AuthManager.shared.signInWithApple(idToken: data.idToken, nonce: data.nonce) { authResult in
                        switch authResult {
                        case .success:
                            guard let self = self else { return }
                            AuthNavigationHelper.continueAfterAppleAuth(
                                from: self,
                                appleName: data.fullName,
                                appleEmail: data.email
                            )
                        case .failure(let error):
                            self?.setLoading(false)
                            self?.showErrorAlert(error.localizedDescription)
                        }
                    }
                case .failure(let error):
                    if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                        self?.showErrorAlert(error.localizedDescription)
                    }
                }
            }
        }
    }
    
    private func showErrorAlert(_ message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
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
        case phoneField:      phoneField.resignFirstResponder()
        default:              textField.resignFirstResponder()
        }
        return true
    }
}
