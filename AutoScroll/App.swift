import SwiftUI
import AVFoundation

@main struct AutoScrollApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @StateObject private var e = Engine.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("AutoScroll").font(.system(size: 28, weight: .bold)).padding(.top, 50)
            Text("2× Volume Up to toggle").font(.subheadline).foregroundColor(.secondary)
            Spacer()
            Button(action: { e.toggle() }) {
                Text(e.on ? "STOP" : "START")
                    .font(.title).fontWeight(.bold).foregroundColor(.white)
                    .frame(width: 150, height: 150)
                    .background(Circle().fill(e.on ? Color.red : Color.blue))
            }
            Picker("", selection: $e.dir) { Text("Up").tag(Engine.Dir.up); Text("Down").tag(Engine.Dir.down) }
                .pickerStyle(.segmented).frame(width: 140)
            Picker("", selection: $e.spd) { Text("1s").tag(Engine.Spd.fast); Text("2.5s").tag(Engine.Spd.medium); Text("5s").tag(Engine.Spd.slow) }
                .pickerStyle(.segmented).frame(width: 160)
            Spacer()
        }
        .onAppear { Audio.shared.start() }
    }
}

// MARK: - Engine

final class Engine: ObservableObject {
    static let shared = Engine()
    @Published var on = false
    @Published var dir: Dir = .up
    @Published var spd: Spd = .medium
    enum Dir: String, CaseIterable { case up, down }
    enum Spd: Double, CaseIterable { case fast = 1, medium = 2.5, slow = 5 }
    
    private var t: DispatchSourceTimer?
    private let s = UIScreen.main.bounds
    
    func toggle() { on ? stop() : start() }
    func start() { guard !on else { return }; on = true; Overlay.show(); tick() }
    func stop() { on = false; t?.cancel(); t = nil; Overlay.hide() }
    
    private func tick() {
        t?.cancel(); t = DispatchSource.makeTimerSource(queue: .global())
        t?.schedule(deadline: .now() + spd.rawValue)
        t?.setEventHandler { [weak self] in self?.swipe() }; t?.resume()
    }
    private func swipe() {
        guard on else { return }
        let w = s.width, h = s.height
        let mx = w * 0.5, ty = h * 0.3, by = h * 0.7
        let sy = dir == .up ? by : ty, ey = dir == .up ? ty : by
        TouchInjector.swipe(fromX: mx, fromY: sy, toX: mx, toY: ey, duration: 0.4)
        Thread.sleep(forTimeInterval: 0.15); tick()
    }
}

// MARK: - Audio + Volume detection

final class Audio: NSObject {
    static let shared = Audio()
    private override init() { super.init() }
    private var p: AVAudioPlayer?, c = 0, l: TimeInterval = 0
    
    func start() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        let sr: Int32 = 8000; let dur = 0.1; let ns = Int(Double(sr)*dur); let ds = ns*2
        var w = Data()
        w.append("RIFF".data(using: .ascii)!); var f = UInt32(36+ds).littleEndian; w.append(Data(bytes: &f, count: 4))
        w.append("WAVE".data(using: .ascii)!); w.append("fmt ".data(using: .ascii)!)
        var z = UInt32(16).littleEndian; w.append(Data(bytes: &z, count: 4))
        var a = UInt16(1).littleEndian; w.append(Data(bytes: &a, count: 2))
        var cc = UInt16(1).littleEndian; w.append(Data(bytes: &cc, count: 2))
        var s = UInt32(sr).littleEndian; w.append(Data(bytes: &s, count: 4))
        var b = UInt32(sr*2).littleEndian; w.append(Data(bytes: &b, count: 4))
        var ba = UInt16(2).littleEndian; w.append(Data(bytes: &ba, count: 2))
        var bp = UInt16(16).littleEndian; w.append(Data(bytes: &bp, count: 2))
        w.append("data".data(using: .ascii)!); var sz = UInt32(ds).littleEndian; w.append(Data(bytes: &sz, count: 4))
        w.append(Data(count: ds))
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("s.wav")
        try? w.write(to: tmp)
        p = try? AVAudioPlayer(contentsOf: tmp); p?.numberOfLoops = -1; p?.volume = 0; p?.play()
        AVAudioSession.sharedInstance().addObserver(self, forKeyPath: "outputVolume", options: .new, context: nil)
    }
    override func observeValue(forKeyPath kp: String?, of obj: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard kp == "outputVolume", let v = change?[.newKey] as? Float else { return }
        let prev = AVAudioSession.sharedInstance().outputVolume
        guard v > prev + 0.01 else { return }
        let now = Date().timeIntervalSince1970
        c = (now - l < 0.6) ? c + 1 : 1; l = now
        if c >= 2 { c = 0; DispatchQueue.main.async { Engine.shared.toggle() }
            let ctrl = NSClassFromString("AVSystemController") as? NSObject.Type
            let shared = ctrl?.perform(NSSelectorFromString("sharedAVSystemController"))?.takeUnretainedValue()
            _ = shared?.perform(NSSelectorFromString("setVolumeTo:forCategory:"), with: max(v-0.3, 0.05), with: "Audio/Video")
        }
    }
}

// MARK: - Floating overlay

final class Overlay: UIWindow {
    static var inst: Overlay?
    static func show() {
        if inst == nil { inst = Overlay(frame: UIScreen.main.bounds); inst?.windowLevel = .alert + 1; inst?.backgroundColor = .clear; inst?.rootViewController = OVC(); inst?.isHidden = false }
        inst?.makeKey()
    }
    static func hide() { inst?.isHidden = true }
    override init(frame: CGRect) { super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }
}

final class OVC: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .clear
        let w = UIScreen.main.bounds.width
        let b = UIButton(frame: CGRect(x: w-52, y: 180, width: 44, height: 44))
        b.backgroundColor = .systemBlue; b.layer.cornerRadius = 22; b.setTitle("AS", for: .normal); b.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        b.addTarget(self, action: #selector(tap), for: .touchUpInside)
        b.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag)))
        b.tag = 1; view.addSubview(b)
    }
    @objc func tap() { Engine.shared.toggle(); update() }
    @objc func drag(_ g: UIPanGestureRecognizer) { let t = g.translation(in: view); g.view!.center.y += t.y; g.setTranslation(.zero, in: view) }
    func update() { view.viewWithTag(1)?.backgroundColor = Engine.shared.on ? .systemRed : .systemBlue }
}
