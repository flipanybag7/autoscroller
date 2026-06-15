import SwiftUI
import AVFoundation

struct ContentView: View {
    @ObservedObject var engine: ScrollerEngine
    @State private var showSettings = false
    
    var body: some View {
        VStack(spacing: 24) {
            Text("AutoScroll")
                .font(.system(size: 32, weight: .bold))
                .padding(.top, 50)
            
            Text("Swipe automation for TrollStore")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: { showSettings = true }) {
                Label("Settings", systemImage: "gearshape.fill")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            
            Button(action: { engine.toggle() }) {
                Text(engine.isRunning ? "STOP" : "START")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(engine.isRunning ? Color.red : Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            
            Text(engine.isRunning ? "Running — tap floating button or 5× Volume Up" : "Tap Start to begin")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(engine: engine)
        }
        .onAppear {
            // Ensure audio session is active for volume detection & background keep-alive
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try? AVAudioSession.sharedInstance().setActive(true)
            
            VolumeDetector.shared.startListening()
            VolumeDetector.shared.onVolumeUpQuintuple = { [weak engine] in
                engine?.toggle()
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var engine: ScrollerEngine
    @Environment(\.presentationMode) var pm
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Direction")) {
                    Picker("", selection: $engine.direction) {
                        ForEach(ScrollerEngine.Direction.allCases) { d in
                            Text(d.label).tag(d)
                        }
                    }.pickerStyle(.segmented)
                }
                Section(header: Text("Speed")) {
                    Picker("", selection: $engine.speed) {
                        ForEach(ScrollerEngine.Speed.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                }
                Section(header: Text("Swipe Duration")) {
                    HStack {
                        Text("\(String(format: "%.2f", engine.duration))s")
                        Slider(value: $engine.duration, in: 0.1...1.5, step: 0.05)
                    }
                }
                Section(header: Text("Randomization")) {
                    Toggle("Random Position", isOn: $engine.randomPosition)
                    Toggle("Random Pause", isOn: $engine.randomPause)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { pm.wrappedValue.dismiss() }
                }
            }
        }
    }
}

// MARK: - Volume button detection

final class VolumeDetector: NSObject {
    static let shared = VolumeDetector()
    var onVolumeUpQuintuple: (() -> Void)?
    
    private var count = 0
    private var lastTime: TimeInterval = 0
    private let listener: OpaquePointer?
    private var audioLevel: Float = 0.5
    
    private init() {
        listener = nil
    }
    
    func startListening() {
        // Use AudioSession output volume observation
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(volumeChanged),
            name: NSNotification.Name(rawValue: "AVSystemController_SystemVolumeDidChangeNotification"),
            object: nil
        )
        // Also observe via KVO on AVAudioSession
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        AVAudioSession.sharedInstance().addObserver(self, forKeyPath: "outputVolume", options: [.new], context: nil)
    }
    
    @objc private func volumeChanged(_ notif: Notification) {
        guard let volume = (notif.userInfo?["AVSystemController_AudioVolumeNotificationParameter"] as? Float) else { return }
        handleVolume(volume)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "outputVolume", let vol = change?[.newKey] as? Float {
            DispatchQueue.main.async { self.handleVolume(vol) }
        }
    }
    
    private func handleVolume(_ volume: Float) {
        let now = Date().timeIntervalSince1970
        if volume > audioLevel + 0.01 {
            // Volume UP detected
            if now - lastTime < 0.5 {
                count += 1
            } else {
                count = 1
            }
            if count >= 5 {
                count = 0
                onVolumeUpQuintuple?()
                // Reset volume back down
                setSystemVolume(max(0.1, volume - 0.3))
            }
        }
        audioLevel = volume
        lastTime = now
    }
    
    private func setSystemVolume(_ level: Float) {
        guard let cls = NSClassFromString("AVSystemController") as? NSObject.Type else { return }
        guard let ctrl = cls.perform(NSSelectorFromString("sharedAVSystemController"))?.takeUnretainedValue() else { return }
        _ = ctrl.perform(NSSelectorFromString("setVolumeTo:forCategory:"), with: level, with: "Audio/Video")
    }
}

private class MPVolumeView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }
}
