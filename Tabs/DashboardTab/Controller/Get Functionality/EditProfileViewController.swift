import UIKit
protocol EditProfileDelegate: AnyObject {
    func didUpdateProfile(name: String?, phone: String?, image: UIImage?)
    
}
class EditProfileViewController: UIViewController {
    
    @IBOutlet weak var tableView: UITableView!
    
    weak var delegate: EditProfileDelegate?
    var name: String?
    var phone: String?
    var profileImage: UIImage?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupFooter()
        tableView.register(UINib(nibName: "EditProfileTableViewCell", bundle: nil),
                           forCellReuseIdentifier: "EditProfileTableViewCell")
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.sectionHeaderTopPadding = 0
    }
}
extension EditProfileViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "EditProfileTableViewCell",
            for: indexPath
        ) as! EditProfileTableViewCell
        
        if indexPath.section == 0 {
            cell.textField.placeholder = "Enter name"
            cell.textField.text = name
        } else {
            cell.textField.placeholder = "Enter mobile number"
            cell.textField.text = phone
            cell.textField.keyboardType = .phonePad
        }
        
        return cell
    }
}

extension EditProfileViewController {
    
    func tableView(_ tableView: UITableView,
                   viewForHeaderInSection section: Int) -> UIView? {
        
        let container = UIView()
        
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])
        
        if section == 0 {
            label.text = "Contact Name"
            label.textColor = UIColor(named: "Black&White")

        } else {
            label.text = "Mobile Number (Optional)"
            label.textColor = UIColor(named: "Black&White")
        }
        
        return container
    }
    
    func tableView(_ tableView: UITableView,
                   heightForHeaderInSection section: Int) -> CGFloat {
        return section == 0 ? 70 : 40
    }
}

extension EditProfileViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    @objc func saveTapped() {
        var updatedName: String?
        var updatedPhone: String?
            
        if let nameCell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? EditProfileTableViewCell {
            updatedName = nameCell.textField.text
        }
            
        if let phoneCell = tableView.cellForRow(at: IndexPath(row: 0, section: 1)) as? EditProfileTableViewCell {
            updatedPhone = phoneCell.textField.text
        }
            
        delegate?.didUpdateProfile(name: updatedName, phone: updatedPhone, image: profileImage)
            
        dismiss(animated: true)
    }
    
    private func setupFooter() {
        let container = UIView()
        
        let button = UIButton(type: .system)
        button.setTitle("Save Changes", for: .normal)
        button.backgroundColor = UIColor(named: "Lime Moss")
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 20
        
        button.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(button)
        
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            button.heightAnchor.constraint(equalToConstant: 50),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])
        
        button.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        
        tableView.tableFooterView = container
        
        container.frame.size.height = 82
    }
    
}
