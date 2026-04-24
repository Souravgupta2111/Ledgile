import UIKit

private let kProfileButtonTag = 7778

extension UIViewController {
    
    /// Adds a circular profile button to the standard navigation bar.
    /// It pins to the bottom right, so it's aligned with the Large Title,
    /// and smoothly shrinks into the compact navigation bar when scrolled.
    func addLargeTitleProfileButton() {
        guard let navigationBar = navigationController?.navigationBar else { return }
        
        // Avoid duplicates
        if navigationBar.viewWithTag(kProfileButtonTag) != nil { return }
        
        let button = UIButton(type: .custom)
        button.tag = kProfileButtonTag
        
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        button.setImage(UIImage(systemName: "person.fill", withConfiguration: config), for: .normal)
        button.tintColor = .label
        button.backgroundColor = UIColor.systemGray5
        button.layer.cornerRadius = 18
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(profileButtonTapped), for: .touchUpInside)
        
        navigationBar.addSubview(button)
        
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: navigationBar.trailingAnchor, constant: -16),
            // Move higher up, closer to the center of the total bar height
            button.bottomAnchor.constraint(equalTo: navigationBar.bottomAnchor, constant: -8),
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44)
        ])
        button.layer.cornerRadius = 22
    }
    
    /// Unhides the profile button (call in viewWillAppear)
    func showLargeTitleProfileButton() {
        navigationController?.navigationBar.viewWithTag(kProfileButtonTag)?.isHidden = false
    }
    
    /// Hides the profile button (call in viewWillDisappear)
    func hideLargeTitleProfileButton() {
        navigationController?.navigationBar.viewWithTag(kProfileButtonTag)?.isHidden = true
    }

    @objc private func profileButtonTapped() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let profileVC = storyboard.instantiateViewController(
            withIdentifier: "ProfileTableViewController"
        ) as? ProfileTableViewController else { return }
        
        navigationController?.pushViewController(profileVC, animated: true)
    }
}
