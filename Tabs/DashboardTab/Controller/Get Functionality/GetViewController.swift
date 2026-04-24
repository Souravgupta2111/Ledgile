import UIKit

class GetViewController: UIViewController {
    var selectedCustomer: Customer?
    @IBOutlet weak var tableView: UITableView!
    
    var customers: [Customer] = []
    
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
        reloadCustomers()
    }
    
    private func reloadCustomers() {
        customers = CreditStore.shared.getAllCustomers()
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

extension GetViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        customers.count
    }
    
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "PersonTableViewCell",
            for: indexPath
        ) as! PersonTableViewCell
        
        let customer = customers[indexPath.row]
        let balance = customer.netBalance
        
        cell.nameLabel.text = customer.name
        
        if balance >= 0 {
            cell.priceLabel.text = "₹\(Int(balance))"
            cell.priceLabel.textColor = balance > 0 ? UIColor(named: "Lime Moss")! : .secondaryLabel
        } else {
            cell.priceLabel.text = "-₹\(Int(-balance))"
            cell.priceLabel.textColor = .systemRed
        }
        
        cell.configureProfile(name: customer.name,
                              image: customer.profileImage)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 12
    }
    

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedCustomer = customers[indexPath.row]
        performSegue(withIdentifier: "customer_details", sender: nil)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "customer_details" {
            let destinationVC = segue.destination as! GetChatInterfaceViewController
            destinationVC.customer = selectedCustomer
            destinationVC.delegate = self
        }
    }
}
extension GetViewController: CustomerDeleteDelegate {
    func didUpdateCustomer(_ customer: Customer) {
        reloadCustomers()
    }
    
    
    func didDeleteCustomer(_ customer: Customer) {
        CreditStore.shared.deleteCustomer(customer)
        reloadCustomers()
    }
    
}

extension GetViewController: EditProfileDelegate {
    func didUpdateProfile(name: String?, phone: String?, image: UIImage?) {
        guard let name = name, !name.isEmpty else { return }
        
        var newCustomer = Customer(
            id: UUID(),
            name: name,
            phone: phone ?? ""
        )
        newCustomer.profileImage = image
        
        CreditStore.shared.addCustomer(newCustomer)
        reloadCustomers()
    }
}
