import UIKit
import AuthenticationServices

class SignInViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var welcomeLabel: UILabel!
    @IBOutlet weak var detailLabel: UILabel!
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
        title = "Sign In"
        styleUI()
        configureFields()
        configureCountryCodeButton()
        updateSendCodeState()
        configureAppleSignIn()
    }

    private func styleUI() {
        phoneField.layer.cornerRadius = 12
        phoneField.layer.borderWidth = 1
        phoneField.layer.borderColor = UIColor.systemGray4.cgColor
        phoneField.clipsToBounds = true
        phoneField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 0))
        phoneField.leftViewMode = .always

        countryCodeButton.layer.cornerRadius = 12
        countryCodeButton.layer.borderWidth = 1
        countryCodeButton.layer.borderColor = UIColor.systemGray4.cgColor
        countryCodeButton.clipsToBounds = true


        sendCodeButton.configuration = nil
        sendCodeButton.layer.cornerRadius = 14
        sendCodeButton.clipsToBounds = true
        sendCodeButton.backgroundColor = UIColor.systemGray3
        sendCodeButton.setTitle("Send Code", for: .normal)
        sendCodeButton.setTitleColor(.white, for: .normal)
        sendCodeButton.setTitleColor(.white, for: .disabled)
        sendCodeButton.setTitleColor(.white, for: .highlighted)
        sendCodeButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
    }

    // MARK: - Configuration

    private func configureFields() {
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



    private func isValidPhone(_ phone: String) -> Bool {
        let digits = phone.filter { $0.isNumber }
        return digits.count == 10
    }

    private func updateSendCodeState() {
        let valid = isValidPhone(phoneField.text ?? "")
        sendCodeButton.isEnabled = valid
        sendCodeButton.alpha = 1.0
        UIView.animate(withDuration: 0.2) {
            self.sendCodeButton.backgroundColor = valid ? .black : UIColor.systemGray3
        }
    }



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
        if !isValidPhone(phoneField.text ?? "") {
            let alert = UIAlertController(
                title: "Invalid Input",
                message: "• Enter a valid 10-digit phone number",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let phone = phoneField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fullPhone = "\(selectedCountryCode)\(phone)"


        // If Supabase is configured, send OTP via AuthManager
        if AuthManager.shared.isConfigured {
            setLoading(true)
            AuthManager.shared.sendOTP(phone: fullPhone) { [weak self] result in
                guard let self = self else { return }
                self.setLoading(false)
                switch result {
                case .success:
                    self.performSegue(withIdentifier: "signInGoToOTP", sender: self)
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
            performSegue(withIdentifier: "signInGoToOTP", sender: self)
        }
    }

    private func setLoading(_ loading: Bool) {
        sendCodeButton.isEnabled = !loading
        sendCodeButton.setTitle(loading ? "Sending..." : "Send Code", for: .normal)
        sendCodeButton.setTitleColor(.white, for: .normal)
        sendCodeButton.setTitleColor(.white, for: .disabled)
        sendCodeButton.alpha = 1.0
        let valid = isValidPhone(phoneField.text ?? "")
        UIView.animate(withDuration: 0.2) {
            self.sendCodeButton.backgroundColor = loading ? UIColor.systemGray2 : (valid ? .black : UIColor.systemGray3)
        }
        phoneField.isEnabled = !loading
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "signInGoToOTP" {
            let otpVC = segue.destination as! OTPViewController
            otpVC.phoneNumber = "\(selectedCountryCode) \(phoneField.text ?? "")"
        }
    }

    // MARK: - Apple Sign In
    
    private let appleSignInButton = ASAuthorizationAppleIDButton(authorizationButtonType: .signIn, authorizationButtonStyle: .black)
    
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
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
