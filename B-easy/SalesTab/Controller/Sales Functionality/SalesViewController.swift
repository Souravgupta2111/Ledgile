
import UIKit
import SwiftUI

class SalesViewController: UIViewController {

    // Storyboard outlets — kept so IB connections don't break even though
    // the SwiftUI view replaces the visual UI.
    @IBOutlet weak var addEntryButton: UIButton!
    @IBOutlet weak var tableView: UITableView!

    private var hostingController: UIHostingController<SalesTabView>?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Hide the storyboard-provided table and button — SwiftUI replaces them.
        tableView?.isHidden = true
        addEntryButton?.isHidden = true

        embedSwiftUIView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh data each time the tab appears (e.g. after adding a sale).
        hostingController?.rootView.reload()
    }

    // MARK: - SwiftUI Hosting

    private func embedSwiftUIView() {
        let salesView = SalesTabView(actions: SalesNavigationActions(
            onManualEntry: { [weak self] in self?.openManualSalesEntry() },
            onVoiceEntry: { [weak self] in self?.openVoiceSalesEntry() },
            onScanEntry: { [weak self] in self?.openScannedSalesEntry() },
            onRevenueTapped: { [weak self] in self?.openRevenue() },
            onProfitTapped: { [weak self] in self?.openProfit() },
            onTransactionTapped: { [weak self] tx in self?.presentBillSheet(for: tx) }
        ))

        let host = UIHostingController(rootView: salesView)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear

        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)

        hostingController = host
    }

    // MARK: - Navigation Actions

    private func openManualSalesEntry() {
        performSegue(withIdentifier: "manual_sales", sender: nil)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        if segue.identifier == "manual_sales" {
            segue.destination.hidesBottomBarWhenPushed = true
        }
    }

    private func openVoiceSalesEntry() {
        guard let voiceVC = storyboard?.instantiateViewController(
            withIdentifier: "VoiceEntryViewController"
        ) as? VoiceEntryViewController else {
            return
        }
        voiceVC.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(voiceVC, animated: true)
    }

    private func openScannedSalesEntry() {
        let scanVC = SalesScanCameraViewController.instantiate(mode: .sale)
        scanVC.onSaleResult = { [weak self] result in
            guard let self = self else { return }
            guard let storyboard = self.storyboard,
                  let salesEntryVC = storyboard.instantiateViewController(withIdentifier: "SalesEntryTableViewController") as? SalesEntryTableViewController else { return }
            salesEntryVC.pendingResult = result
            salesEntryVC.entryMode = .camera
            salesEntryVC.hidesBottomBarWhenPushed = true
            self.navigationController?.pushViewController(salesEntryVC, animated: true)
        }
        scanVC.modalPresentationStyle = .fullScreen
        present(scanVC, animated: true)
    }

    private func openRevenue() {
        performSegue(withIdentifier: "revenue_segue", sender: nil)
    }

    private func openProfit() {
        performSegue(withIdentifier: "profit_segue", sender: nil)
    }

    // MARK: - IBActions (kept for any remaining storyboard connections)

    @IBAction func addEntryTapped(_ sender: UIButton) {
        // Fallback — the SwiftUI buttons handle navigation now,
        // but keep this in case the storyboard button is still wired.
        openManualSalesEntry()
    }

    @IBAction func salesScanButtonTapped(_ sender: UIButton) {
        openScannedSalesEntry()
    }

    @IBAction func manualSalesEntryTapped(_ sender: UIButton) {
        openManualSalesEntry()
    }

    @IBAction func voiceEntryTapped(_ sender: UIButton) {
        openVoiceSalesEntry()
    }
}
