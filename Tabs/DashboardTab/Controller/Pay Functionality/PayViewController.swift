
import UIKit

class PayViewController: UIViewController {
    var selectedSupplier: Supplier?
    @IBOutlet weak var tableView: UITableView!
    
    var suppliers: [Supplier] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.register(UINib(nibName: "PersonTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "PersonTableViewCell")
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .systemGray6
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadSuppliers()
    }
    
    private func reloadSuppliers() {
        suppliers = CreditStore.shared.getAllSuppliers()
        tableView.reloadData()
    }
    
    @IBAction func addCustomerTapped(_ sender: UIButton) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let vc = storyboard.instantiateViewController(
            withIdentifier: "EditProfileViewController"
        ) as! EditProfileViewController
        vc.delegate = self
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
        
    }
}
extension PayViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        suppliers.count
    }
    
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "PersonTableViewCell",
            for: indexPath
        ) as! PersonTableViewCell
        
        let supplier = suppliers[indexPath.row]
        let balance = supplier.netBalance
        
        cell.nameLabel.text = supplier.name
        
        if balance > 0 {
            // You owe the supplier
            cell.priceLabel.text = "₹\(Int(balance))"
            cell.priceLabel.textColor = .systemRed
        } else if balance < 0 {
            // Supplier owes you
            cell.priceLabel.text = "₹\(Int(-balance))"
            cell.priceLabel.textColor = UIColor(named: "Lime Moss")!
        } else {
            cell.priceLabel.text = "₹0"
            cell.priceLabel.textColor = .secondaryLabel
        }
        
        cell.configureProfile(name: supplier.name,
                              image: supplier.profileImage)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 12
    }
    

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedSupplier = suppliers[indexPath.row]
        performSegue(withIdentifier: "supplier_details", sender: nil)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "supplier_details" {
            let destinationVC = segue.destination as! PayChatInterfaceViewController
            destinationVC.supplier = selectedSupplier
            destinationVC.delegate = self
        }
    }
}
extension PayViewController: SupplierDeleteDelegate {
    func didUpdateSupplier(_ supplier: Supplier) {
        reloadSuppliers()
    }
    
    
    func didDeleteSupplier(_ supplier: Supplier) {
        CreditStore.shared.deleteSupplier(supplier)
        reloadSuppliers()
    }
    
}
extension PayViewController: EditProfileDelegate {
    func didUpdateProfile(name: String?, phone: String?, image: UIImage?) {
        guard let name = name, !name.isEmpty else { return }
        
        var newSupplier = Supplier(
            id: UUID(),
            name: name,
            phone: phone ?? ""
        )
        newSupplier.profileImage = image
        
        CreditStore.shared.addSupplier(newSupplier)
        reloadSuppliers()
    }
}
