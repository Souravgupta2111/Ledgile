import UIKit

/// Slim top/bottom waveform strip: 24 bars animating with mic/speech level.
/// Matches app design tokens (Lime Moss on systemGray6).
final class LiveWaveformView: UIView {

    private var bars: [UIView] = []
    private var displayLink: CADisplayLink?
    private var phase: CGFloat = 0
    /// 0...1 external level (mic RMS or TTS energy). Animates idle when 0.
    var level: CGFloat = 0
    var isLive: Bool = false { didSet { isLive ? start() : stop() } }

    private let barCount = 24

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
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fillEqually
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
        for _ in 0..<barCount {
            let b = UIView()
            b.backgroundColor = lime.withAlphaComponent(0.85)
            b.layer.cornerRadius = 2
            b.translatesAutoresizingMaskIntoConstraints = false
            b.heightAnchor.constraint(equalToConstant: 4).isActive = true
            stack.addArrangedSubview(b)
            bars.append(b)
        }
    }

    private func start() {
        stop()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        phase += 0.22
        let base = max(level, isLive ? 0.12 : 0.0)
        for (i, bar) in bars.enumerated() {
            let wave = abs(sin(phase + CGFloat(i) * 0.55))
            let h = 4 + (base * 26 * wave) + (isLive ? 2 * wave : 0)
            bar.constraints.forEach { c in
                if c.firstAttribute == .height { c.constant = min(h, 32) }
            }
            bar.alpha = 0.45 + 0.55 * wave * min(max(base + 0.3, 0), 1)
        }
    }

    deinit { stop() }
}
