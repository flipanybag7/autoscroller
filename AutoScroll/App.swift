import SwiftUI
import UIKit

@main
struct AutoScrollApp: App {
    @StateObject private var engine = ScrollerEngine()
    
    var body: some Scene {
        WindowGroup {
            ContentView(engine: engine)
        }
    }
}

// Floating panel window that overlays other apps
final class FloatingPanel: UIWindow {
    static let shared = FloatingPanel()
    private let engine = ScrollerEngine.shared
    
    private init() {
        let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first
        if let scene = scene {
            super.init(windowScene: scene)
        } else {
            super.init(frame: UIScreen.main.bounds)
        }
        
        self.windowLevel = .statusBar + 100
        self.backgroundColor = .clear
        self.isUserInteractionEnabled = true
        self.rootViewController = FloatingViewController(engine: engine)
        self.isHidden = true
        self.rootViewController?.view.backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func show() {
        isHidden = false
        makeKeyAndVisible()
    }
    
    func hide() {
        isHidden = true
    }
}

final class FloatingViewController: UIViewController {
    let engine: ScrollerEngine
    private var panelY: CGFloat = 200
    private var isExpanded = false
    
    let button: UIButton = {
        let b = UIButton(frame: CGRect(x: 0, y: 0, width: 56, height: 56))
        b.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.85)
        b.layer.cornerRadius = 28
        b.setTitle("AS", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        b.setTitleColor(.white, for: .normal)
        b.layer.shadowColor = UIColor.black.cgColor
        b.layer.shadowOffset = CGSize(width: 0, height: 2)
        b.layer.shadowRadius = 8
        b.layer.shadowOpacity = 0.4
        return b
    }()
    
    let expandView = UIView()
    
    init(engine: ScrollerEngine) {
        self.engine = engine
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let screen = UIScreen.main.bounds
        button.center = CGPoint(x: screen.width - 40, y: 200)
        button.addTarget(self, action: #selector(toggleExpand), for: .touchUpInside)
        button.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan)))
        view.addSubview(button)
        
        expandView.frame = CGRect(x: screen.width - 200, y: 120, width: 180, height: 220)
        expandView.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.9)
        expandView.layer.cornerRadius = 16
        expandView.layer.shadowColor = UIColor.black.cgColor
        expandView.layer.shadowOffset = CGSize(width: 0, height: 4)
        expandView.layer.shadowRadius = 12
        expandView.layer.shadowOpacity = 0.3
        expandView.isHidden = true
        view.addSubview(expandView)
        
        buildExpandedPanel()
        
        engine.onStateChange = { [weak self] in
            self?.updateButtonAppearance()
        }
    }
    
    func buildExpandedPanel() {
        let y: CGFloat = 15
        let w = expandView.bounds.width
        let h: CGFloat = 44
        
        let statusLabel = UILabel(frame: CGRect(x: 15, y: y, width: w - 30, height: h))
        statusLabel.text = "AutoScroll"
        statusLabel.font = .systemFont(ofSize: 16, weight: .bold)
        statusLabel.textAlignment = .center
        statusLabel.tag = 1
        expandView.addSubview(statusLabel)
        
        let toggleBtn = UIButton(frame: CGRect(x: 20, y: y + 50, width: w - 40, height: h))
        toggleBtn.setTitle("START", for: .normal)
        toggleBtn.backgroundColor = .systemBlue
        toggleBtn.layer.cornerRadius = 10
        toggleBtn.tag = 2
        toggleBtn.addTarget(self, action: #selector(toggleScroll), for: .touchUpInside)
        expandView.addSubview(toggleBtn)
        
        let seg = UISegmentedControl(items: ["Up", "Down", "Rnd"])
        seg.frame = CGRect(x: 15, y: y + 105, width: w - 30, height: 30)
        seg.selectedSegmentIndex = 0
        seg.tag = 3
        seg.addTarget(self, action: #selector(dirChanged(_:)), for: .valueChanged)
        expandView.addSubview(seg)
        
        let speedSeg = UISegmentedControl(items: ["1s", "2.5s", "5s"])
        speedSeg.frame = CGRect(x: 15, y: y + 148, width: w - 30, height: 30)
        speedSeg.selectedSegmentIndex = 1
        speedSeg.tag = 4
        speedSeg.addTarget(self, action: #selector(speedChanged(_:)), for: .valueChanged)
        expandView.addSubview(speedSeg)
    }
    
    @objc func toggleExpand() {
        isExpanded.toggle()
        expandView.isHidden = !isExpanded
    }
    
    @objc func toggleScroll() {
        engine.toggle()
        updateButtonAppearance()
    }
    
    @objc func dirChanged(_ seg: UISegmentedControl) {
        let dirs: [ScrollerEngine.Direction] = [.up, .down, .random]
        engine.direction = dirs[seg.selectedSegmentIndex]
    }
    
    @objc func speedChanged(_ seg: UISegmentedControl) {
        let speeds: [ScrollerEngine.Speed] = [.fast, .medium, .slow]
        engine.speed = speeds[seg.selectedSegmentIndex]
    }
    
    @objc func pan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: view)
        g.view!.center = CGPoint(x: g.view!.center.x + t.x, y: g.view!.center.y + t.y)
        g.setTranslation(.zero, in: view)
        expandView.center = CGPoint(x: g.view!.center.x - 62, y: g.view!.center.y - 80)
    }
    
    func updateButtonAppearance() {
        button.backgroundColor = engine.isRunning
            ? UIColor.systemRed.withAlphaComponent(0.85)
            : UIColor.systemBlue.withAlphaComponent(0.85)
        if let toggle = expandView.viewWithTag(2) as? UIButton {
            toggle.setTitle(engine.isRunning ? "STOP" : "START", for: .normal)
            toggle.backgroundColor = engine.isRunning ? .systemRed : .systemBlue
        }
    }
}
