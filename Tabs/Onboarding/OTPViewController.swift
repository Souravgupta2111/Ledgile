import UIKit

class OTPViewController: UIViewController, UITextFieldDelegate {

    // MARK: - IBOutlets (connect these in Storyboard)

    @IBOutlet weak var subtitleLabel: UILabel!

    @IBOutlet weak var otpField1: UITextField!
    @IBOutlet weak var otpField2: UITextField!
    @IBOutlet weak var otpField3: UITextField!
    @IBOutlet weak var otpField4: UITextField!
    @IBOutlet weak var otpField5: UITextField!
    @IBOutlet weak var otpField6: UITextField!

    @IBOutlet weak var verifyButton: UIButton!
    @IBOutlet weak var resendButton: UIButton!

    // MARK: - Properties

    var phoneNumber: String = ""
    private var resendSeconds = 30
    private var resendTimer: Timer?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Verify OTP"
        subtitleLabel.text = "Enter 6-digit code sent to \(phoneNumber)"
        styleUI()
        setupOTPFields()
        updateVerifyState()
        startResendTimer()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resendTimer?.invalidate()
    }

    // MARK: - Styling

    private func styleUI() {
        verifyButton.layer.cornerRadius = 20
        verifyButton.clipsToBounds = true
    }

    

    private var allFields: [UITextField] {
        return [otpField1, otpField2, otpField3, otpField4, otpField5, otpField6]
    }

    private func setupOTPFields() {
        for field in allFields {
            field.delegate = self
            field.keyboardType = .numberPad
            field.textAlignment = .center
            field.font = .systemFont(ofSize: 24, weight: .bold)
            field.layer.cornerRadius = 12
            field.layer.borderWidth = 1.5
            field.layer.borderColor = UIColor.systemGray4.cgColor
            field.clipsToBounds = true
            field.tintColor = .systemBlue
            field.backgroundColor = .systemBackground
        }
        otpField1.becomeFirstResponder()
    }

    private func highlightField(_ field: UITextField, active: Bool) {
        UIView.animate(withDuration: 0.2) {
            field.layer.borderColor = active ? UIColor.systemBlue.cgColor : UIColor.systemGray4.cgColor
            field.layer.borderWidth = active ? 2.0 : 1.5
            field.transform = active ? CGAffineTransform(scaleX: 1.05, y: 1.05) : .identity
        }
    }

    private func updateVerifyState() {
        let complete = allFields.allSatisfy { ($0.text?.count ?? 0) == 1 }
        verifyButton.isEnabled = complete
        UIView.animate(withDuration: 0.2) {
            self.verifyButton.alpha = complete ? 1.0 : 0.5
        }
    }

    // Resend Timer

    private func startResendTimer() {
        resendSeconds = 30
        resendButton.isEnabled = false
        resendButton.setTitle("Resend in 30s", for: .normal)

        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.resendSeconds -= 1
            if self.resendSeconds <= 0 {
                timer.invalidate()
                self.resendButton.isEnabled = true
                self.resendButton.setTitle("Resend Code", for: .normal)
            } else {
                self.resendButton.setTitle("Resend in \(self.resendSeconds)s", for: .normal)
            }
        }
    }

  

    func textFieldDidBeginEditing(_ textField: UITextField) {
        allFields.forEach { highlightField($0, active: false) }
        highlightField(textField, active: true)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        highlightField(textField, active: false)
    }

    func textField(_ textField: UITextField,
                   shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {

        if string.isEmpty {
            textField.text = ""
            moveToPrevious(textField)
            updateVerifyState()
            return false
        }

        guard string.count == 1,
              CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: string)) else {
            return false
        }

        textField.text = string
        moveToNext(textField)
        updateVerifyState()
        return false
    }

    private func moveToNext(_ textField: UITextField) {
        let fields = allFields
        guard let idx = fields.firstIndex(of: textField), idx + 1 < fields.count else {
            textField.resignFirstResponder()
            return
        }
        fields[idx + 1].becomeFirstResponder()
    }

    private func moveToPrevious(_ textField: UITextField) {
        let fields = allFields
        guard let idx = fields.firstIndex(of: textField), idx > 0 else { return }
        fields[idx - 1].becomeFirstResponder()
    }

    // MARK: - Actions

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @IBAction func verifyTapped(_ sender: UIButton) {
        let otp = allFields.compactMap { $0.text }.joined()
        guard otp.count == 6 else { return }

        // If Supabase is configured, verify the OTP via AuthManager
        if AuthManager.shared.isConfigured {
            setLoading(true)
            AuthManager.shared.verifyOTP(phone: phoneNumber, code: otp) { [weak self] result in
                guard let self = self else { return }
                self.setLoading(false)
                switch result {
                case .success:
                    self.navigateToMainApp()
                case .failure(let error):
                    let alert = UIAlertController(
                        title: "Verification Failed",
                        message: error.localizedDescription,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.navigationController?.present(alert, animated: true)
                }
            }
        } else {
            // Supabase not configured — demo mode, accept any OTP
            navigateToMainApp()
        }
    }

    private func navigateToMainApp() {
        // Mark user as logged in locally (for session persistence)
        UserDefaults.standard.set(true, forKey: "userDidCompleteOnboarding")

        let alert = UIAlertController(title: "Success", message: "OTP verified successfully!", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let mainTabBarController = storyboard.instantiateViewController(withIdentifier: "MainTabBarController")
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.rootViewController = mainTabBarController
                UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: nil, completion: nil)
            }
        })
        
        self.navigationController?.present(alert, animated: true)
    }

    private func setLoading(_ loading: Bool) {
        verifyButton.isEnabled = !loading
        verifyButton.setTitle(loading ? "Verifying..." : "Verify", for: .normal)
        verifyButton.alpha = loading ? 0.6 : 1.0
        allFields.forEach { $0.isEnabled = !loading }
    }

    @IBAction func resendTapped(_ sender: UIButton) {
        allFields.forEach { $0.text = "" }
        updateVerifyState()
        otpField1.becomeFirstResponder()
        startResendTimer()

        // If Supabase is configured, resend OTP
        if AuthManager.shared.isConfigured {
            AuthManager.shared.sendOTP(phone: phoneNumber) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    let alert = UIAlertController(title: "Code Sent", message: "A new OTP has been sent to \(self.phoneNumber)", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.navigationController?.present(alert, animated: true)
                case .failure(let error):
                    let alert = UIAlertController(title: "Resend Failed", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.navigationController?.present(alert, animated: true)
                }
            }
        } else {
            let alert = UIAlertController(title: "Code Sent", message: "A new OTP has been sent to \(phoneNumber)", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.navigationController?.present(alert, animated: true)
        }
    }
}
