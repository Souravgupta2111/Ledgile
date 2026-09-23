import UIKit
import SwiftUI

class StockViewController: UIViewController {

    @IBOutlet private weak var tableView: UITableView!
    
    private var hostingController: UIHostingController<StockTabView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView?.isHidden = true
        embedSwiftUIView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh data when the view appears
    }

    private func embedSwiftUIView() {
        let stockView = StockTabView(actions: StockNavigationActions(
            onManualEntry: { [weak self] in self?.openManualPurchaseEntry() },
            onVoiceEntry: { [weak self] in self?.openVoicePurchaseEntry() },
            onScanEntry: { [weak self] in self?.openPurchaseScanner() },
            onItemTapped: { [weak self] item in self?.openItemProfile(for: item) }
        ))

        let host = UIHostingController(rootView: stockView)
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

    private func openManualPurchaseEntry() {
        performSegue(withIdentifier: "AddPurchaseFromStock", sender: nil)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        if segue.identifier == "AddPurchaseFromStock" {
            segue.destination.hidesBottomBarWhenPushed = true
        } else if segue.identifier == "showItemProfileSegue" {
            if let dest = segue.destination as? ItemProfileTableViewController, let item = sender as? Item {
                dest.item = item
            }
        }
    }

    private func openVoicePurchaseEntry() {
        guard let voiceVC = storyboard?.instantiateViewController(
            withIdentifier: "VoicePurchaseEntryViewController"
        ) as? VoicePurchaseEntryViewController else {
            return
        }

        voiceVC.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(voiceVC, animated: true)
    }

    private func openPurchaseScanner() {
        let scanVC = PurchaseScanCameraViewController.instantiate(mode: .purchase)
        scanVC.onPurchaseResult = { [weak self] result in
            guard let self = self else { return }
            guard let storyboard = self.storyboard,
                  let purchaseVC = storyboard.instantiateViewController(withIdentifier: "AddPurchaseViewController") as? AddPurchaseViewController else { return }
            purchaseVC.pendingPurchaseResult = result
            purchaseVC.entryMode = .camera
            purchaseVC.hidesBottomBarWhenPushed = true
            self.navigationController?.pushViewController(purchaseVC, animated: true)
        }
        scanVC.modalPresentationStyle = .fullScreen
        present(scanVC, animated: true)
    }

    private func openItemProfile(for item: Item) {
        performSegue(withIdentifier: "showItemProfileSegue", sender: item)
    }
}
