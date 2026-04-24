import UIKit

extension UIButton {
    func applyGlassEffect(cornerRadius: CGFloat = 25) {
        // Clear background
        self.backgroundColor = .clear
        self.subviews.filter { $0 is UIVisualEffectView }.forEach { $0.removeFromSuperview() }
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.isUserInteractionEnabled = false
        blurView.frame = self.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurView.layer.cornerRadius = cornerRadius
        blurView.clipsToBounds = true
        blurView.layer.borderWidth = 1.0
        blurView.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOpacity = 0.15
        self.layer.shadowRadius = 8
        self.layer.shadowOffset = CGSize(width: 0, height: 4)
        
        self.insertSubview(blurView, at: 0)
        if let imageView = self.imageView {
            self.bringSubviewToFront(imageView)
        }
        if let titleLabel = self.titleLabel {
            self.bringSubviewToFront(titleLabel)
        }
    }
}
