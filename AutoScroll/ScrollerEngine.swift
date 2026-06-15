import Foundation
import UIKit
import AVFoundation

final class ScrollerEngine: ObservableObject {
    static let shared = ScrollerEngine()
    
    @Published var isRunning = false
    @Published var direction: Direction = .up
    @Published var speed: Speed = .medium
    @Published var duration: Double = 0.5
    @Published var randomPosition: Bool = true
    @Published var randomPause: Bool = true
    
    var onStateChange: (() -> Void)?
    
    enum Direction: String, CaseIterable, Identifiable {
        case up, down, random
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        func resolve() -> Direction {
            if case .random = self { return Bool.random() ? .up : .down }
            return self
        }
    }
    
    enum Speed: Double, CaseIterable, Identifiable {
        case slow = 5.0, medium = 2.5, fast = 1.0
        var id: Double { rawValue }
        var label: String {
            switch self {
            case .slow: return "Slow (5s)"
            case .medium: return "Medium (2.5s)"
            case .fast: return "Fast (1s)"
            }
        }
    }
    
    private var timer: DispatchSourceTimer?
    private var bgPlayer: AVAudioPlayer?
    private let screen = UIScreen.main.bounds
    
    func toggle() {
        isRunning ? stop() : start()
    }
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        onStateChange?()
        enableBackgroundAudio()
        FloatingPanel.shared.show()
        scheduleNext()
    }
    
    func stop() {
        isRunning = false
        onStateChange?()
        timer?.cancel()
        timer = nil
        bgPlayer?.stop()
        FloatingPanel.shared.hide()
    }
    
    private func scheduleNext() {
        timer?.cancel()
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "autoscroll.timer"))
        let pause = nextPause()
        timer?.schedule(deadline: .now() + pause)
        timer?.setEventHandler { [weak self] in self?.performSwipe() }
        timer?.resume()
    }
    
    private func performSwipe() {
        guard isRunning else { return }
        
        let dir = direction.resolve()
        let (fx, fy, tx, ty) = coords(dir)
        
        DispatchQueue.main.async {
            TouchInjector.swipe(fromX: fx, fromY: fy, toX: tx, toY: ty, duration: self.duration)
        }
        Thread.sleep(forTimeInterval: 0.1)
        scheduleNext()
    }
    
    private func coords(_ dir: Direction) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let w = screen.width, h = screen.height
        let mx = randomPosition ? w * CGFloat.random(in: 0.2...0.8) : w * 0.5
        let ty = randomPosition ? h * CGFloat.random(in: 0.20...0.40) : h * 0.30
        let by = randomPosition ? h * CGFloat.random(in: 0.60...0.85) : h * 0.70
        return dir == .up ? (mx, by, mx, ty) : (mx, ty, mx, by)
    }
    
    private func nextPause() -> TimeInterval {
        let base = speed.rawValue
        guard randomPause else { return base }
        return base + Double.random(in: -base * 0.4 ... base * 0.4)
    }
    
    private func enableBackgroundAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { print("Audio session error:", error) }
        
        // Generate silent WAV
        let sampleRate: Int32 = 8000
        let numSamples = Int(Float(sampleRate) * 0.1)
        let dataSize = numSamples * 2
        var wav = Data()
        wav.append("RIFF".data(using: .ascii)!)
        var sz = UInt32(36 + dataSize).littleEndian; wav.append(Data(bytes: &sz, count: 4))
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        var fmtSz = UInt32(16).littleEndian; wav.append(Data(bytes: &fmtSz, count: 4))
        var af = UInt16(1).littleEndian; wav.append(Data(bytes: &af, count: 2))
        var ch = UInt16(1).littleEndian; wav.append(Data(bytes: &ch, count: 2))
        var sr = UInt32(sampleRate).littleEndian; wav.append(Data(bytes: &sr, count: 4))
        var br = UInt32(sampleRate * 2).littleEndian; wav.append(Data(bytes: &br, count: 4))
        var ba = UInt16(2).littleEndian; wav.append(Data(bytes: &ba, count: 2))
        var bps = UInt16(16).littleEndian; wav.append(Data(bytes: &bps, count: 2))
        wav.append("data".data(using: .ascii)!)
        var dsz = UInt32(dataSize).littleEndian; wav.append(Data(bytes: &dsz, count: 4))
        wav.append(Data(count: dataSize))
        
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("silence.wav")
        try? wav.write(to: tmp)
        bgPlayer = try? AVAudioPlayer(contentsOf: tmp)
        bgPlayer?.numberOfLoops = -1
        bgPlayer?.volume = 0
        bgPlayer?.play()
    }
}
