import Foundation
import UIKit
import Combine
import AVFoundation

/// Drives the autoscroll with configurable direction, speed, duration, and randomness.
final class ScrollerEngine: ObservableObject {
    
    // MARK: - Published settings
    
    @Published var isRunning = false
    
    @Published var direction: Direction = .up
    @Published var speed: Speed = .medium
    @Published var duration: Double = 0.5
    @Published var randomPosition: Bool = true
    @Published var randomPause: Bool = true
    
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
        case slow   = 5.0
        case medium = 2.5
        case fast   = 1.0
        case custom = 0
        
        var id: Double { rawValue }
        var label: String {
            switch self {
            case .slow:   return "Slow (5s)"
            case .medium: return "Medium (2.5s)"
            case .fast:   return "Fast (1s)"
            case .custom: return "Custom"
            }
        }
    }
    
    // MARK: - State
    
    private var timer: DispatchSourceTimer?
    private var bgPlayer: AVAudioPlayer?
    private let screen = UIScreen.main.bounds
    
    // MARK: - Toggle
    
    func toggle() {
        isRunning ? stop() : start()
    }
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        enableBackgroundAudio()
        scheduleNext()
    }
    
    func stop() {
        isRunning = false
        timer?.cancel()
        timer = nil
        bgPlayer?.stop()
    }
    
    // MARK: - Swipe execution
    
    private func scheduleNext() {
        let queue = DispatchQueue(label: "autoscroll.timer")
        timer?.cancel()
        timer = DispatchSource.makeTimerSource(queue: queue)
        
        let pause = nextPause()
        timer?.schedule(deadline: .now() + pause)
        timer?.setEventHandler { [weak self] in
            self?.performSwipe()
        }
        timer?.resume()
    }
    
    private func performSwipe() {
        guard isRunning else { return }
        
        let dir = direction.resolve()
        let (fx, fy, tx, ty) = computeCoordinates(direction: dir)
        
        DispatchQueue.main.async {
            TouchInjector.swipe(fromX: fx, fromY: fy, toX: tx, toY: ty, duration: self.duration)
        }
        
        // Small delay after swipe before scheduling next
        Thread.sleep(forTimeInterval: 0.1)
        scheduleNext()
    }
    
    // MARK: - Coordinate calculation
    
    private func computeCoordinates(direction: Direction) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let w = screen.width
        let h = screen.height
        
        let midX: CGFloat = randomPosition
            ? w * CGFloat.random(in: 0.2...0.8)
            : w * 0.5
        
        let topY: CGFloat = randomPosition
            ? h * CGFloat.random(in: 0.20...0.40)
            : h * 0.30
        
        let bottomY: CGFloat = randomPosition
            ? h * CGFloat.random(in: 0.60...0.85)
            : h * 0.70
        
        switch direction {
        case .up:   return (midX, bottomY, midX, topY)
        case .down: return (midX, topY, midX, bottomY)
        case .random: break
        }
        fatalError("direction.resolve() should have resolved .random")
    }
    
    // MARK: - Timing helpers
    
    private func nextPause() -> TimeInterval {
        let base = speed == .custom ? 2.5 : speed.rawValue
        guard randomPause else { return base }
        // +/- 40% random variation
        let variation = base * 0.4
        return base + Double.random(in: -variation...variation)
    }
    
    // MARK: - Background keep-alive (silent audio loop)
    
    private func enableBackgroundAudio() {
        guard let url = Bundle.main.url(forResource: "silence", withExtension: "m4a") else {
            // Generate a tiny silent audio file in memory
            _generateSilenceAsset()
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            bgPlayer = try AVAudioPlayer(contentsOf: url)
            bgPlayer?.numberOfLoops = -1
            bgPlayer?.volume = 0
            bgPlayer?.play()
        } catch {
            print("Audio session error:", error)
        }
    }
    
    /// Generate a 0.1-second silent WAV in the tmp directory and play it in a loop
    private func _generateSilenceAsset() {
        // Create minimal PCM WAV: 8000 Hz, 16-bit mono, 0.1s
        let sampleRate: Int32 = 8000
        let duration: Float = 0.1
        let numSamples = Int(Float(sampleRate) * duration)
        let dataSize = numSamples * 2  // 16-bit = 2 bytes/sample
        
        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        var fileSize = UInt32(36 + dataSize).littleEndian; header.append(Data(bytes: &fileSize, count: 4))
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        var fmtSize = UInt32(16).littleEndian;          header.append(Data(bytes: &fmtSize, count: 4))
        var audioFormat = UInt16(1).littleEndian;       header.append(Data(bytes: &audioFormat, count: 2)) // PCM
        var channels = UInt16(1).littleEndian;          header.append(Data(bytes: &channels, count: 2))
        var sr = UInt32(sampleRate).littleEndian;       header.append(Data(bytes: &sr, count: 4))
        var byteRate = UInt32(sampleRate * 2).littleEndian; header.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = UInt16(2).littleEndian;        header.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample = UInt16(16).littleEndian;    header.append(Data(bytes: &bitsPerSample, count: 2))
        header.append("data".data(using: .ascii)!)
        var dSize = UInt32(dataSize).littleEndian;      header.append(Data(bytes: &dSize, count: 4))
        
        // silence = all zeros
        let silence = Data(count: dataSize)
        let wav = header + silence
        
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("silence.wav")
        try? wav.write(to: tmp)
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            bgPlayer = try AVAudioPlayer(contentsOf: tmp)
            bgPlayer?.numberOfLoops = -1
            bgPlayer?.volume = 0
            bgPlayer?.play()
        } catch {
            print("Silent audio error:", error)
        }
    }
}
