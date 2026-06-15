import SwiftUI
import AVFoundation

@main
struct AutoScrollApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Main view

struct ContentView: View {
    @StateObject private var engine = ScrollerEngine()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("AutoScroll").font(.system(size: 28, weight: .bold)).padding(.top, 50)
            Text("2× Volume Up to toggle from any app").font(.subheadline).foregroundColor(.secondary)
            Spacer()
            
            Button(action: { engine.toggle() }) {
                Text(engine.isRunning ? "STOP" : "START")
                    .font(.title).fontWeight(.bold).foregroundColor(.white)
                    .frame(width: 150, height: 150)
                    .background(Circle().fill(engine.isRunning ? Color.red : Color.blue))
            }
            
            Picker("Direction", selection: $engine.direction) {
                Text("Up").tag(ScrollerEngine.Direction.up)
                Text("Down").tag(ScrollerEngine.Direction.down)
            }.pickerStyle(.segmented).frame(width: 140)
            
            Picker("Speed", selection: $engine.speed) {
                Text("1s").tag(ScrollerEngine.Speed.fast)
                Text("2.5s").tag(ScrollerEngine.Speed.medium)
                Text("5s").tag(ScrollerEngine.Speed.slow)
            }.pickerStyle(.segmented).frame(width: 140)
            
            Spacer()
        }
        .onAppear { AudioManager.shared.start() }
    }
}

// MARK: - Silent audio for background keep-alive & volume detection

final class AudioManager: NSObject {
    static let shared = AudioManager()
    private override init() { super.init() }
    
    private var player: AVAudioPlayer?
    private var volCount = 0, lastVol: TimeInterval = 0
    
    func start() {
        // Play silent WAV so app stays alive + volume KVO works in background
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        
        let sr: Int32 = 8000, dur: Double = 0.1
        let ns = Int(Double(sr) * dur), ds = ns * 2
        var wav = Data()
        wav.append("RIFF".data(using: .ascii)!); var fs = UInt32(36+ds).littleEndian; wav.append(Data(bytes: &fs, count: 4))
        wav.append("WAVE".data(using: .ascii)!); wav.append("fmt ".data(using: .ascii)!)
        var fz = UInt32(16).littleEndian; wav.append(Data(bytes: &fz, count: 4))
        var af = UInt16(1).littleEndian; wav.append(Data(bytes: &af, count: 2))
        var ch = UInt16(1).littleEndian; wav.append(Data(bytes: &ch, count: 2))
        var srl = UInt32(sr).littleEndian; wav.append(Data(bytes: &srl, count: 4))
        var br = UInt32(sr*2).littleEndian; wav.append(Data(bytes: &br, count: 4))
        var ba = UInt16(2).littleEndian; wav.append(Data(bytes: &ba, count: 2))
        var bp = UInt16(16).littleEndian; wav.append(Data(bytes: &bp, count: 2))
        wav.append("data".data(using: .ascii)!); var sz = UInt32(ds).littleEndian; wav.append(Data(bytes: &sz, count: 4))
        wav.append(Data(count: ds)) // silence
        
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("s.wav")
        try? wav.write(to: tmp)
        player = try? AVAudioPlayer(contentsOf: tmp)
        player?.numberOfLoops = -1
        player?.volume = 0
        player?.play()
        
        AVAudioSession.sharedInstance().addObserver(self, forKeyPath: "outputVolume", options: .new, context: nil)
    }
    
    override func observeValue(forKeyPath kp: String?, of obj: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard kp == "outputVolume", let new = change?[.newKey] as? Float else { return }
        let prev = AVAudioSession.sharedInstance().outputVolume
        guard new > prev + 0.01 else { return }
        
        let now = Date().timeIntervalSince1970
        volCount = (now - lastVol < 0.6) ? volCount + 1 : 1
        lastVol = now
        
        if volCount >= 2 {
            volCount = 0
            DispatchQueue.main.async { ScrollerEngine.shared.toggle() }
            // Reset volume down
            let c = NSClassFromString("AVSystemController") as? NSObject.Type
            let s = c?.perform(NSSelectorFromString("sharedAVSystemController"))?.takeUnretainedValue()
            _ = s?.perform(NSSelectorFromString("setVolumeTo:forCategory:"), with: max(new - 0.3, 0.05), with: "Audio/Video")
        }
    }
}

// MARK: - Scroller engine (uses WDA silently in background)

final class ScrollerEngine: ObservableObject {
    static let shared = ScrollerEngine()
    
    @Published var isRunning = false
    @Published var direction: Direction = .up
    @Published var speed: Speed = .medium
    
    enum Direction: String, CaseIterable, Identifiable {
        case up, down
        var id: String { rawValue }
    }
    enum Speed: Double, CaseIterable, Identifiable {
        case fast = 1.0, medium = 2.5, slow = 5.0
        var id: Double { rawValue }
    }
    
    private var timer: DispatchSourceTimer?
    private let wdaURL = "http://127.0.0.1:8100"
    private var sessionId: String?
    private let screen = UIScreen.main.bounds
    
    func toggle() { isRunning ? stop() : start() }
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        ensureWDA()
        schedule()
    }
    
    func stop() {
        isRunning = false
        timer?.cancel()
        timer = nil
    }
    
    private func schedule() {
        timer?.cancel()
        timer = DispatchSource.makeTimerSource(queue: .global())
        timer?.schedule(deadline: .now() + speed.rawValue)
        timer?.setEventHandler { [weak self] in self?.swipe() }
        timer?.resume()
    }
    
    private func swipe() {
        guard isRunning, let sid = sessionId else { return }
        let w = screen.width, h = screen.height
        let mx = Int(w * 0.5)
        let ty = Int(h * 0.3), by = Int(h * 0.7)
        let (sy, ey) = direction == .up ? (by, ty) : (ty, by)
        
        let body = "{\"fromX\":\(mx),\"fromY\":\(sy),\"toX\":\(mx),\"toY\":\(ey),\"duration\":0.4}"
        _ = wdaPOST("/session/\(sid)/wda/dragfromtoforduration", body)
        Thread.sleep(forTimeInterval: 0.2)
        schedule()
    }
    
    private func ensureWDA() {
        guard sessionId == nil else { return }
        
        // Check if WDA is already running
        if let status = wdaGET("/status"), status.contains("sessionId") {
            extractSession(from: status)
            return
        }
        
        // Launch WDA silently via LSApplicationWorkspace
        let bundleId = "com.facebook.WebDriverAgentRunner.xctrunner"
        let ws = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type
        let shared = ws?.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue()
        _ = shared?.perform(NSSelectorFromString("openApplicationWithBundleID:"), with: bundleId)
        
        // Wait for WDA to start (up to 15 seconds)
        for _ in 0..<30 {
            Thread.sleep(forTimeInterval: 0.5)
            if let status = wdaGET("/status"), status.contains("sessionId") {
                extractSession(from: status)
                return
            }
        }
    }
    
    private func extractSession(from json: String) {
        guard let r = json.range(of: "\"sessionId\":\"") else { return }
        let s = json[r.upperBound...]
        guard let e = s.firstIndex(of: "\"") else { return }
        sessionId = String(s[..<e])
    }
    
    private func wdaGET(_ path: String) -> String? {
        var result: String?
        let sem = DispatchSemaphore(value: 0)
        var req = URLRequest(url: URL(string: "\(wdaURL)\(path)")!, timeoutInterval: 3)
        req.httpMethod = "GET"
        URLSession.shared.dataTask(with: req) { d, _, _ in
            if let d = d { result = String(data: d, encoding: .utf8) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 3)
        return result
    }
    
    private func wdaPOST(_ path: String, _ body: String) -> String? {
        var result: String?
        let sem = DispatchSemaphore(value: 0)
        var req = URLRequest(url: URL(string: "\(wdaURL)\(path)")!, timeoutInterval: 3)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data(using: .utf8)
        URLSession.shared.dataTask(with: req) { d, _, _ in
            if let d = d { result = String(data: d, encoding: .utf8) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 3)
        return result
    }
}
