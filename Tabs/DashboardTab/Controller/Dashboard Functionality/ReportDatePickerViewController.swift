import UIKit

final class ReportDatePickerViewController: UIViewController {
    var reportType: ReportType = .profitAndLoss
    var onGenerate: ((Date, Date) -> Void)?
    var selectedIndex: Int = 2
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var customStack: UIStackView!
    @IBOutlet weak var fromPicker: UIDatePicker!
    @IBOutlet weak var toPicker: UIDatePicker!
    
    @IBOutlet weak var segmentedControl: UISegmentedControl!
    
    @IBAction func segmentChanged(_ sender: UISegmentedControl) {
        selectedIndex = sender.selectedSegmentIndex
        handleSegmentChange()
    }
    
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
        handleSegmentChange()
    }


    func configureFromStoryboard() {
        fromPicker.date = Date()
        fromPicker.maximumDate = Date()

        toPicker.date = Date()
        toPicker.maximumDate = Date()

        customStack.isHidden = true
        customStack.alpha = 0

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


    private func handleSegmentChange() {
        let isCustom = selectedIndex == 3
        UIView.animate(withDuration: 0.25) {
            self.customStack.isHidden = !isCustom
            self.customStack.alpha = isCustom ? 1 : 0
        }
    }

    @objc private func generateTapped() {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        let from: Date
        let to: Date

        switch selectedIndex {
        case 0:
            from = startOfToday
            to = now
        case 1:
            from = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
            to = now
        case 2:
            from = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
            to = now
        case 3:
            from = calendar.startOfDay(for: fromPicker.date)
            to = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: toPicker.date))?.addingTimeInterval(-1) ?? toPicker.date
        default:
            from = startOfToday
            to = now
        }

        dismiss(animated: true) { [weak self] in
            self?.onGenerate?(from, to)
        }
    }
}
