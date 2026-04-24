import UIKit
import QuickLook

class ReportsViewController: UIViewController {

    private var reportTypes: [ReportType] {
        var base = ReportType.allCases.filter { 
            $0 != .gstr1 && $0 != .gstr3b && 
            $0 != .hsnSummary && $0 != .inputTaxRegister && $0 != .outputTaxRegister 
        }
        
        let dm = AppDataModel.shared.dataModel
        if let settings = try? dm.db.getSettings(), settings.isGSTRegistered {
            if settings.gstScheme == "regular" {
                base.append(.gstr1)
                base.append(.gstr3b)
                base.append(.hsnSummary)
                base.append(.inputTaxRegister)
                base.append(.outputTaxRegister)
            } else if settings.gstScheme == "composition" {
                // Composition scheme mostly doesn't have ITC GSTR-3B flows like regular does, 
                // but let's just expose GSTR-1 for outward supplies or whatever logic applies.
                // Keeping it simple for the user request, if regular -> show both.
                base.append(.hsnSummary)
            }
        }
        return base
    }

    private var pdfPreviewDataSource: PDFPreviewDataSource?

    @IBOutlet weak var tableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.dataSource = self
        tableView.delegate = self
        
        tableView.register(UINib(nibName: "LabelTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "LabelTableViewCell")
        
        tableView.backgroundColor = .systemGray6
        tableView.separatorStyle = .none
        tableView.sectionHeaderTopPadding = 12
    }
}


extension ReportsViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return reportTypes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(
            withIdentifier: "LabelTableViewCell",
            for: indexPath
        ) as! LabelTableViewCell

        let isFirst = indexPath.row == 0
        let isLast = indexPath.row == reportTypes.count - 1

        cell.applyCornerMask(isFirst: isFirst, isLast: isLast)

        let report = reportTypes[indexPath.row]
        cell.titleLabel.text = report.rawValue
        cell.selectionStyle = .default

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let report = reportTypes[indexPath.row]
        handleReportTap(report)
    }
}

extension ReportsViewController: QLPreviewControllerDataSource {

    func handleReportTap(_ report: ReportType) {
        if report.needsDateRange {

            guard let picker = storyboard?.instantiateViewController(
                withIdentifier: "ReportDatePickerViewController"
            ) as? ReportDatePickerViewController else {
                return
            }

            picker.reportType = report
            picker.onGenerate = { [weak self] from, to in
                self?.generateAndPreview(report: report, from: from, to: to)
            }

            present(picker, animated: true)

        } else {
            let cal = Calendar.current
            let from = cal.date(byAdding: .year, value: -10, to: Date()) ?? Date()
            generateAndPreview(report: report, from: from, to: Date())
        }
    }

    private func generateAndPreview(report: ReportType, from: Date, to: Date) {

        guard let pdfURL = ReportGenerator.shared.generateReport(type: report, from: from, to: to) else {
            let alert = UIAlertController(title: "Error", message: "Failed to generate report.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        let item = PDFPreviewItem(url: pdfURL, name: report.rawValue)
        pdfPreviewDataSource = PDFPreviewDataSource(item: item)

        let ql = QLPreviewController()
        ql.dataSource = self
        present(ql, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        pdfPreviewDataSource?.item ?? PDFPreviewItem(url: URL(fileURLWithPath: ""), name: "")
    }
}
