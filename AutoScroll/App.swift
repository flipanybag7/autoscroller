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
            
            Picker("", selection: $engine.direction) {
                Text("Up").tag(ScrollerEngine.Direction.up)
                Text("Down").tag(ScrollerEngine.Direction.down)
            }.pickerStyle(.segmented).frame(width: 140)
            
            Picker("", selection: $engine.speed) {
                Text("1s").tag(ScrollerEngine.Speed.fast)
                Text("2.5s").tag(ScrollerEngine.Speed.medium)
                Text("5s").tag(ScrollerEngine.Speed.slow)
            }.pickerStyle(.segmented).frame(width: 160)
            
            Spacer()
        }
        .onAppear { AudioManager.shared.start() }
    }
}

// MARK: - Silent audio + 2× volume detection

final class AudioManager: NSObject {
    static let shared = AudioManager()
    private override init() { super.init() }
    
    private var player: AVAudioPlayer?
    private var count = 0, last: TimeInterval = 0
    
    func start() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        let wav = silentWAV()
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("s.wav")
        try? wav.write(to: tmp)
        player = try? AVAudioPlayer(contentsOf: tmp)
        player?.numberOfLoops = -1; player?.volume = 0; player?.play()
        AVAudioSession.sharedInstance().addObserver(self, forKeyPath: "outputVolume", options: .new, context: nil)
        
        // Also show the floating overlay
        Overlay.show()
    }
    
    override func observeValue(forKeyPath kp: String?, of obj: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard kp == "outputVolume", let v = change?[.newKey] as? Float else { return }
        let prev = AVAudioSession.sharedInstance().outputVolume
        guard v > prev + 0.01 else { return }
        let now = Date().timeIntervalSince1970
        count = (now - last < 0.6) ? count + 1 : 1; last = now
        if count >= 2 {
            count = 0
            DispatchQueue.main.async { ScrollerEngine.shared.toggle(); Overlay.show() }
            let c = NSClassFromString("AVSystemController") as? NSObject.Type
            let s = c?.perform(NSSelectorFromString("sharedAVSystemController"))?.takeUnretainedValue()
            _ = s?.perform(NSSelectorFromString("setVolumeTo:forCategory:"), with: max(v - 0.3, 0.05), with: "Audio/Video")
        }
    }
    
    private func silentWAV() -> Data {
        let sr: Int32 = 8000, dur: Double = 0.1, ns = Int(Double(sr)*dur), ds = ns*2
        var d = Data()
        d.append("RIFF".data(using: .ascii)!); var f = UInt32(36+ds).littleEndian; d.append(Data(bytes: &f, count: 4))
        d.append("WAVE".data(using: .ascii)!); d.append("fmt ".data(using: .ascii)!)
        var z = UInt32(16).littleEndian; d.append(Data(bytes: &z, count: 4))
        var a = UInt16(1).littleEndian; d.append(Data(bytes: &a, count: 2))
        var c = UInt16(1).littleEndian; d.append(Data(bytes: &c, count: 2))
        var s = UInt32(sr).littleEndian; d.append(Data(bytes: &s, count: 4))
        var b = UInt32(sr*2).littleEndian; d.append(Data(bytes: &b, count: 4))
        var ba = UInt16(2).littleEndian; d.append(Data(bytes: &ba, count: 2))
        var bp = UInt16(16).littleEndian; d.append(Data(bytes: &bp, count: 2))
        d.append("data".data(using: .ascii)!); var sz = UInt32(ds).littleEndian; d.append(Data(bytes: &sz, count: 4))
        d.append(Data(count: ds)); return d
    }
}

// MARK: - Floating overlay window

final class Overlay: UIWindow {
    private static var instance: Overlay?
    
    static func show() {
        if instance == nil {
            instance = Overlay(frame: UIScreen.main.bounds)
            instance?.windowLevel = .alert + 1
            instance?.backgroundColor = .clear
            instance?.rootViewController = OverlayVC()
            instance?.isHidden = false
        }
        instance?.makeKey()
    }
    
    override init(frame: CGRect) { super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }
}

final class OverlayVC: UIViewController {
    private let panel = UIView()
    private var panelY: CGFloat = 180
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        
        let btn = UIButton(frame: CGRect(x: UIScreen.main.bounds.width - 52, y: panelY, width: 44, height: 44))
        btn.backgroundColor = .systemBlue; btn.layer.cornerRadius = 22
        btn.setTitle("AS", for: .normal); btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        btn.addTarget(self, action: #selector(togglePanel), for: .touchUpInside)
        btn.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag)))
        btn.tag = 1; view.addSubview(btn)
        
        panel.frame = CGRect(x: UIScreen.main.bounds.width - 180, y: panelY - 5, width: 160, height: 150)
        panel.backgroundColor = .systemGray5.withAlphaComponent(0.92); panel.layer.cornerRadius = 14
        panel.isHidden = true; view.addSubview(panel)
        
        let title = UILabel(frame: CGRect(x: 10, y: 10, width: 140, height: 20))
        title.text = "AutoScroll"; title.font = .systemFont(ofSize: 13, weight: .bold); title.textAlignment = .center
        panel.addSubview(title)
        
        let toggle = UIButton(frame: CGRect(x: 20, y: 36, width: 120, height: 34))
        toggle.setTitle("START", for: .normal); toggle.backgroundColor = .systemBlue
        toggle.layer.cornerRadius = 8; toggle.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        toggle.addTarget(self, action: #selector(tapToggle), for: .touchUpInside); toggle.tag = 10
        panel.addSubview(toggle)
        
        let dir = UISegmentedControl(items: ["Up", "Down"])
        dir.frame = CGRect(x: 14, y: 78, width: 132, height: 26); dir.selectedSegmentIndex = 0
        dir.addTarget(self, action: #selector(dirChange), for: .valueChanged)
        panel.addSubview(dir)
        
        let spd = UISegmentedControl(items: ["1s", "2.5s", "5s"])
        spd.frame = CGRect(x: 14, y: 110, width: 132, height: 26); spd.selectedSegmentIndex = 1
        spd.addTarget(self, action: #selector(speedChange), for: .valueChanged)
        panel.addSubview(spd)
        
        updateUI()
    }
    
    @objc func togglePanel() { panel.isHidden.toggle() }
    @objc func tapToggle() { ScrollerEngine.shared.toggle(); updateUI() }
    @objc func dirChange(_ s: UISegmentedControl) { ScrollerEngine.shared.direction = s.selectedSegmentIndex == 0 ? .up : .down }
    @objc func speedChange(_ s: UISegmentedControl) { ScrollerEngine.shared.speed = [.fast, .medium, .slow][s.selectedSegmentIndex] }
    @objc func drag(_ g: UIPanGestureRecognizer) { let t = g.translation(in: view); view.viewWithTag(1)?.center.y += t.y; panel.center.y += t.y; g.setTranslation(.zero, in: view) }
    
    func updateUI() {
        let r = ScrollerEngine.shared.isRunning
        view.viewWithTag(1)?.backgroundColor = r ? .systemRed : .systemBlue
        if let tb = panel.viewWithTag(10) as? UIButton { tb.setTitle(r ? "STOP" : "START", for: .normal); tb.backgroundColor = r ? .systemRed : .systemBlue }
    }
}

// MARK: - Scroller engine

final class ScrollerEngine: ObservableObject {
    static let shared = ScrollerEngine()
    
    @Published var isRunning = false
    @Published var direction: Direction = .up
    @Published var speed: Speed = .medium
    
    enum Direction: String, CaseIterable, Identifiable { case up, down; var id: String { rawValue } }
    enum Speed: Double, CaseIterable, Identifiable { case fast = 1.0, medium = 2.5, slow = 5.0; var id: Double { rawValue } }
    
    private var timer: DispatchSourceTimer?
    private let screen = UIScreen.main.bounds
    
    func toggle() { isRunning ? stop() : start() }
    func start() { guard !isRunning else { return }; isRunning = true; schedule() }
    func stop() { isRunning = false; timer?.cancel(); timer = nil }
    
    private func schedule() {
        timer?.cancel(); timer = DispatchSource.makeTimerSource(queue: .global())
        timer?.schedule(deadline: .now() + speed.rawValue)
        timer?.setEventHandler { [weak self] in self?.swipe() }; timer?.resume()
    }
    
    private func swipe() {
        guard isRunning else { return }
        let w = screen.width, h = screen.height
        let mx = w * 0.5, ty = h * 0.3, by = h * 0.7
        TouchInjector.swipe(fromX: mx, fromY: direction == .up ? by : ty, toX: mx, toY: direction == .up ? ty : by, duration: 0.4)
        Thread.sleep(forTimeInterval: 0.15)
        schedule()
    }
}
