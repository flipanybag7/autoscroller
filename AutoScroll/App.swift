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

// MARK: - Floating overlay window

final class OverlayWindow: UIWindow {
    static let shared: OverlayWindow = {
        let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first
        let w = scene != nil ? OverlayWindow(windowScene: scene!) : OverlayWindow(frame: UIScreen.main.bounds)
        w.windowLevel = .alert + 1
        w.backgroundColor = .clear
        w.isUserInteractionEnabled = true
        w.rootViewController = OverlayVC()
        w.isHidden = false
        return w
    }()
    
    override init(frame: CGRect) { super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError() }
}

final class OverlayVC: UIViewController {
    private let panel = UIView()
    private var panelY: CGFloat = 150
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        
        let screen = UIScreen.main.bounds
        
        // Collapsed button
        let btn = UIButton(frame: CGRect(x: screen.width - 52, y: panelY, width: 44, height: 44))
        btn.backgroundColor = .systemBlue
        btn.layer.cornerRadius = 22
        btn.setTitle("AS", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        btn.addTarget(self, action: #selector(togglePanel), for: .touchUpInside)
        btn.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragBtn)))
        btn.tag = 1
        view.addSubview(btn)
        
        // Panel
        panel.frame = CGRect(x: screen.width - 180, y: panelY - 10, width: 160, height: 170)
        panel.backgroundColor = UIColor.systemGray5.withAlphaComponent(0.92)
        panel.layer.cornerRadius = 14
        panel.isHidden = true
        view.addSubview(panel)
        
        let title = UILabel(frame: CGRect(x: 10, y: 12, width: 140, height: 20))
        title.text = "AutoScroll"
        title.font = .systemFont(ofSize: 14, weight: .bold)
        title.textAlignment = .center
        panel.addSubview(title)
        
        let toggle = UIButton(frame: CGRect(x: 20, y: 40, width: 120, height: 36))
        toggle.setTitle("START", for: .normal)
        toggle.backgroundColor = .systemBlue
        toggle.layer.cornerRadius = 8
        toggle.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        toggle.addTarget(self, action: #selector(tapToggle), for: .touchUpInside)
        toggle.tag = 10
        panel.addSubview(toggle)
        
        let dir = UISegmentedControl(items: ["Up", "Down"])
        dir.frame = CGRect(x: 14, y: 86, width: 132, height: 28)
        dir.selectedSegmentIndex = 0
        dir.addTarget(self, action: #selector(dirChange), for: .valueChanged)
        dir.tag = 11
        panel.addSubview(dir)
        
        let speed = UISegmentedControl(items: ["1s", "2.5s", "5s"])
        speed.frame = CGRect(x: 14, y: 122, width: 132, height: 28)
        speed.selectedSegmentIndex = 1
        speed.addTarget(self, action: #selector(speedChange), for: .valueChanged)
        speed.tag = 12
        panel.addSubview(speed)
        
        ScrollerEngine.shared.onStateChange = { [weak self] in self?.updateUI() }
        updateUI()
    }
    
    @objc func togglePanel() {
        panel.isHidden = !panel.isHidden
    }
    
    @objc func tapToggle() {
        ScrollerEngine.shared.toggle()
        updateUI()
    }
    
    @objc func dirChange(_ s: UISegmentedControl) {
        ScrollerEngine.shared.direction = s.selectedSegmentIndex == 0 ? .up : .down
    }
    
    @objc func speedChange(_ s: UISegmentedControl) {
        ScrollerEngine.shared.speed = [.fast, .medium, .slow][s.selectedSegmentIndex]
    }
    
    @objc func dragBtn(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: view)
        for v in [view.viewWithTag(1), panel] { v?.center.y += t.y }
        g.setTranslation(.zero, in: view)
        panelY = view.viewWithTag(1)?.center.y ?? panelY
    }
    
    func updateUI() {
        let running = ScrollerEngine.shared.isRunning
        view.viewWithTag(1)?.backgroundColor = running ? UIColor.systemRed : UIColor.systemBlue
        if let t = panel.viewWithTag(10) as? UIButton {
            t.setTitle(running ? "STOP" : "START", for: .normal)
            t.backgroundColor = running ? .systemRed : .systemBlue
        }
    }
}

// MARK: - Volume detector via IOHIDEvent monitoring

final class VolumeDetector {
    static let shared = VolumeDetector()
    
    private var volUpCount = 0
    private var lastVolUp: TimeInterval = 0
    
    func start() {
        // KVO on output volume
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        AVAudioSession.sharedInstance().addObserver(self, forKeyPath: "outputVolume", options: .new, context: nil)
    }
    
    func onVolumeUp() {
        let now = Date().timeIntervalSince1970
        if now - lastVolUp < 0.5 { volUpCount += 1 } else { volUpCount = 1 }
        lastVolUp = now
        
        if volUpCount >= 5 {
            volUpCount = 0
            DispatchQueue.main.async {
                OverlayWindow.shared.isHidden = false
                OverlayWindow.shared.makeKey()
                // Reset volume
                self.setVolume(max(self.currentVolume() - 0.3, 0.05))
            }
        }
    }
    
    private func currentVolume() -> Float {
        return AVAudioSession.sharedInstance().outputVolume
    }
    
    private func setVolume(_ vol: Float) {
        let ctrl = NSClassFromString("AVSystemController") as? NSObject.Type
        let shared = ctrl?.perform(NSSelectorFromString("sharedAVSystemController"))?.takeUnretainedValue()
        _ = shared?.perform(NSSelectorFromString("setVolumeTo:forCategory:"), with: vol, with: "Audio/Video")
    }
}

extension VolumeDetector {
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "outputVolume", let new = change?[.newKey] as? Float else { return }
        let prev = AVAudioSession.sharedInstance().outputVolume
        if new > prev + 0.001 { DispatchQueue.main.async { self.onVolumeUp() } }
    }
}

// MARK: - Main content view (minimal)

struct ContentView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("AutoScroll")
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 60)
            Text("5× Volume Up to open controls from any app")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
            Button(action: { ScrollerEngine.shared.toggle() }) {
                Text(ScrollerEngine.shared.isRunning ? "STOP" : "START")
                    .font(.title2).fontWeight(.bold).foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(ScrollerEngine.shared.isRunning ? Color.red : Color.blue)
                    .cornerRadius(14)
            }.padding(.horizontal, 50)
            Spacer()
        }
    }
}
