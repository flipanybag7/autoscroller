import SwiftUI
import AVFoundation

@main
struct AutoScrollApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { VolumeDetector.shared.start() }
        }
    }
}

// MARK: - Volume detection (KVO on output volume)

final class VolumeDetector: NSObject {
    static let shared = VolumeDetector()
    private override init() { super.init() }
    
    private var count = 0
    private var last: TimeInterval = 0
    private var player: AVAudioPlayer?
    
    func start() {
        // Play silent audio so app stays alive and volume KVO works in background
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        
        let wav = silentWAV()
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("s.wav")
        try? wav.write(to: tmp)
        player = try? AVAudioPlayer(contentsOf: tmp)
        player?.numberOfLoops = -1
        player?.volume = 0
        player?.play()
        
        AVAudioSession.sharedInstance().addObserver(self, forKeyPath: "outputVolume", options: .new, context: nil)
    }
    
    override func observeValue(forKeyPath kp: String?, of obj: Any?, change: [NSKeyValueChangeKey: Any]?, ctx: UnsafeMutableRawPointer?) {
        guard kp == "outputVolume", let v = change?[.newKey] as? Float else { return }
        let prev = AVAudioSession.sharedInstance().outputVolume
        if v > prev + 0.01 {
            let now = Date().timeIntervalSince1970
            count = (now - last < 0.6) ? count + 1 : 1
            last = now
            if count >= 5 {
                count = 0
                DispatchQueue.main.async { ScrollerEngine.shared.toggle() }
                // Reset volume back
                let ctrl = NSClassFromString("AVSystemController") as? NSObject.Type
                let shared = ctrl?.perform(NSSelectorFromString("sharedAVSystemController"))?.takeUnretainedValue()
                _ = shared?.perform(NSSelectorFromString("setVolumeTo:forCategory:"), with: max(v - 0.3, 0.05), with: "Audio/Video")
            }
        }
    }
    
    private func silentWAV() -> Data {
        let sr: Int32 = 8000, dur = 0.1, ns = Int(Float(sr) * dur), ds = ns * 2
        var d = Data()
        d.append("RIFF".data(using: .ascii)!); var fs = UInt32(36+ds).littleEndian; d.append(Data(bytes: &fs, count: 4))
        d.append("WAVE".data(using: .ascii)!); d.append("fmt ".data(using: .ascii)!)
        var fz = UInt32(16).littleEndian; d.append(Data(bytes: &fz, count: 4))
        var af = UInt16(1).littleEndian; d.append(Data(bytes: &af, count: 2))
        var ch = UInt16(1).littleEndian; d.append(Data(bytes: &ch, count: 2))
        var sr2 = UInt32(sr).littleEndian; d.append(Data(bytes: &sr2, count: 4))
        var br = UInt32(sr*2).littleEndian; d.append(Data(bytes: &br, count: 4))
        var ba = UInt16(2).littleEndian; d.append(Data(bytes: &ba, count: 2))
        var bp = UInt16(16).littleEndian; d.append(Data(bytes: &bp, count: 2))
        d.append("data".data(using: .ascii)!); var sz = UInt32(ds).littleEndian; d.append(Data(bytes: &sz, count: 4))
        d.append(Data(count: ds))
        return d
    }
}

// MARK: - Content view

struct ContentView: View {
    @ObservedObject var engine = ScrollerEngine.shared
    
    var body: some View {
        VStack(spacing: 24) {
            Text("AutoScroll")
                .font(.system(size: 30, weight: .bold))
                .padding(.top, 60)
            
            Text("5× Volume Up to toggle from any app")
                .font(.subheadline).foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: { engine.toggle() }) {
                Text(engine.isRunning ? "STOP" : "START")
                    .font(.title).fontWeight(.bold).foregroundColor(.white)
                    .frame(width: 160, height: 160)
                    .background(Circle().fill(engine.isRunning ? Color.red : Color.blue))
            }
            
            HStack(spacing: 20) {
                Picker("", selection: $engine.direction) {
                    Text("Up").tag(ScrollerEngine.Direction.up)
                    Text("Down").tag(ScrollerEngine.Direction.down)
                }.pickerStyle(.segmented).frame(width: 140)
                
                Picker("", selection: $engine.speed) {
                    Text("1s").tag(ScrollerEngine.Speed.fast)
                    Text("2.5s").tag(ScrollerEngine.Speed.medium)
                    Text("5s").tag(ScrollerEngine.Speed.slow)
                }.pickerStyle(.segmented).frame(width: 140)
            }
            
            Text(engine.isRunning ? "Scrolling — volume triggers work in background" : "Tap Start or press Volume Up 5×")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30)
            
            Spacer()
        }
    }
}
