import UIKit

/// ChatGPT-voice-style orb in app colours: a cloudy sphere of 3 rotating
/// Lime Moss / teal / white blobs over a soft core. States:
/// listening = breathe + mic level scale, thinking = fast swirl,
/// speaking = radiate with TTS level. CoreAnimation only.
final class LiveOrbView: UIView {

    enum Mode {
        case idle, listening, thinking, speaking
    }

    var mode: Mode = .idle { didSet { applyMode() } }
    /// 0...1 mic/speech level driving scale + blob spread.
    var level: CGFloat = 0 { didSet { applyLevel() } }

    private let clip = UIView()          // circular mask container (breathe anim here)
    private let pulse = UIView()         // mic/speech level scale (UIView transform)
    private let spinner = UIView()       // rotates the blobs (layer rotation)
    private var blobs: [CAGradientLayer] = []
    private let core = CAGradientLayer() // bright cloudy centre
    private let ring = CAShapeLayer()    // outer glow ring

    private var breathe: CABasicAnimation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        let lime = UIColor(named: "Lime Moss") ?? .systemGreen

        clip.backgroundColor = .clear
        clip.clipsToBounds = true
        clip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clip)
        NSLayoutConstraint.activate([
            clip.centerXAnchor.constraint(equalTo: centerXAnchor),
            clip.centerYAnchor.constraint(equalTo: centerYAnchor),
            clip.widthAnchor.constraint(equalTo: widthAnchor),
            clip.heightAnchor.constraint(equalTo: heightAnchor)
        ])

        pulse.translatesAutoresizingMaskIntoConstraints = false
        pulse.backgroundColor = .clear
        clip.addSubview(pulse)
        NSLayoutConstraint.activate([
            pulse.centerXAnchor.constraint(equalTo: clip.centerXAnchor),
            pulse.centerYAnchor.constraint(equalTo: clip.centerYAnchor),
            pulse.widthAnchor.constraint(equalTo: clip.widthAnchor),
            pulse.heightAnchor.constraint(equalTo: clip.heightAnchor)
        ])

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.backgroundColor = .clear
        pulse.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: pulse.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: pulse.centerYAnchor),
            spinner.widthAnchor.constraint(equalTo: pulse.widthAnchor, multiplier: 1.35),
            spinner.heightAnchor.constraint(equalTo: pulse.heightAnchor, multiplier: 1.35)
        ])

        // Soft base disc so the orb reads as a sphere on any background.
        let base = CAGradientLayer()
        base.type = .radial
        // Dynamic base: light in light mode, dark in dark mode.
        let baseCenter = UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 0.18, alpha: 0.95)
                : UIColor.white.withAlphaComponent(0.95)
        }
        let baseEdge = UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 0.12, alpha: 0.9)
                : UIColor.systemGray6.withAlphaComponent(0.9)
        }
        base.colors = [baseCenter.cgColor, baseEdge.cgColor]
        base.startPoint = CGPoint(x: 0.5, y: 0.42)
        base.endPoint = CGPoint(x: 1, y: 1)
        base.name = "base"
        clip.layer.addSublayer(base)
        blobs.append(base)

        // Three colour blobs orbiting inside.
        let blobCols: [[CGColor]] = [
            [lime.withAlphaComponent(0.85).cgColor, lime.withAlphaComponent(0).cgColor],
            [UIColor.systemTeal.withAlphaComponent(0.75).cgColor, UIColor.systemTeal.withAlphaComponent(0).cgColor],
            [UIColor.systemMint.withAlphaComponent(0.6).cgColor, UIColor.systemMint.withAlphaComponent(0).cgColor]
        ]
        for (i, cols) in blobCols.enumerated() {
            let g = CAGradientLayer()
            g.type = .radial
            g.colors = cols
            g.startPoint = CGPoint(x: 0.5, y: 0.5)
            g.endPoint = CGPoint(x: 1, y: 1)
            g.name = "blob\(i)"
            spinner.layer.addSublayer(g)
            blobs.append(g)
        }

        // Bright cloudy core on top.
        core.type = .radial
        core.colors = [UIColor.white.withAlphaComponent(0.9).cgColor,
                       UIColor.white.withAlphaComponent(0).cgColor]
        core.startPoint = CGPoint(x: 0.5, y: 0.5)
        core.endPoint = CGPoint(x: 1, y: 1)
        clip.layer.addSublayer(core)

        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = lime.withAlphaComponent(0.45).cgColor
        ring.lineWidth = 2.5
        layer.addSublayer(ring)
        applyMode()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let d = min(bounds.width, bounds.height)
        clip.layer.cornerRadius = d / 2
        for l in clip.layer.sublayers ?? [] { l.frame = clip.bounds }
        for l in spinner.layer.sublayers ?? [] {
            let s = spinner.bounds.width * 0.62
            l.frame = CGRect(x: (spinner.bounds.width - s) / 2,
                             y: (spinner.bounds.height - s) / 2 - s * 0.18,
                             width: s, height: s)
            l.cornerRadius = s / 2
        }
        core.frame = clip.bounds
        core.cornerRadius = min(clip.bounds.width, clip.bounds.height) / 2
        ring.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3)).cgPath
    }

    // MARK: - states

    private func applyMode() {
        spinner.layer.removeAnimation(forKey: "spin")
        clip.layer.removeAnimation(forKey: "breathe")
        breathe = nil
        switch mode {
        case .idle:
            layer.opacity = 0.85
        case .listening:
            layer.opacity = 1
            startSpin(duration: 14)
            startBreathe(from: 1.0, to: 1.06, duration: 1.6)
        case .thinking:
            layer.opacity = 1
            startSpin(duration: 3.2)
            startBreathe(from: 1.0, to: 1.03, duration: 0.7)
        case .speaking:
            layer.opacity = 1
            startSpin(duration: 7)
            startBreathe(from: 1.0, to: 1.1, duration: 0.9)
        }
    }

    private func applyLevel() {
        let clamped = min(max(level, 0), 1)
        let s = 1.0 + clamped * (mode == .speaking ? 0.22 : 0.14)
        // Level goes on `pulse` only — `clip` carries the breathe animation,
        // `spinner` carries rotation. Separate targets = no fight.
        pulse.transform = CGAffineTransform(scaleX: s, y: s)
        core.opacity = 0.75 + Float(clamped) * 0.25
    }

    private func startSpin(duration: Double) {
        let r = CABasicAnimation(keyPath: "transform.rotation.z")
        r.fromValue = 0
        r.toValue = Double.pi * 2
        r.duration = duration
        r.repeatCount = .infinity
        spinner.layer.add(r, forKey: "spin")
    }

    private func startBreathe(from: CGFloat, to: CGFloat, duration: Double) {
        let a = CABasicAnimation(keyPath: "transform.scale")
        a.fromValue = from
        a.toValue = to
        a.duration = duration
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        clip.layer.add(a, forKey: "breathe")
        breathe = a
    }
}
