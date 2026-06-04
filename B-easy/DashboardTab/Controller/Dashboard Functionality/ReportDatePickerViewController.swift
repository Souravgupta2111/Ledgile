import UIKit

final class ReportDatePickerViewController: UIViewController {
    var reportType: ReportType = .profitAndLoss
    var onGenerate: ((Date, Date) -> Void)?
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var customStack: UIStackView!
    @IBOutlet weak var fromPicker: UIDatePicker!
    @IBOutlet weak var toPicker: UIDatePicker!

    let generateButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        titleLabel.text = "\(reportType.rawValue)"
        if let sheet = sheetPresentationController {
            sheet.detents = [UISheetPresentationController.Detent.medium()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24
        }
        configureFromStoryboard()
    }


    func configureFromStoryboard() {
        fromPicker.date = Date()
        fromPicker.maximumDate = Date()

        toPicker.date = Date()
        toPicker.maximumDate = Date()

        // Always show the date pickers (no segment to toggle)
        customStack.isHidden = false
        customStack.alpha = 1

        generateButton.setTitle("Generate Report", for: .normal)
        generateButton.setImage(UIImage(systemName: "doc.text.fill"), for: .normal)
        generateButton.tintColor = .white
        generateButton.setTitleColor(.white, for: .normal)
        generateButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        generateButton.backgroundColor = UIColor.systemBlue
        generateButton.layer.cornerRadius = 20
        generateButton.translatesAutoresizingMaskIntoConstraints = false
        generateButton.addTarget(self, action: #selector(generateTapped), for: .touchUpInside)

        generateButton.configuration = {
            var config = UIButton.Configuration.filled()
            config.image = UIImage(systemName: "doc.text.fill")
            config.title = "Generate Report"
            config.imagePadding = 8
            config.baseBackgroundColor = UIColor(named: "Lime Moss")
            return config
        }()

        view.addSubview(generateButton)

        NSLayoutConstraint.activate([
            generateButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            generateButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            generateButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            generateButton.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    @objc private func generateTapped() {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: fromPicker.date)
        let to = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: toPicker.date))?.addingTimeInterval(-1) ?? toPicker.date

        dismiss(animated: true) { [weak self] in
            self?.onGenerate?(from, to)
        }
    }
}
