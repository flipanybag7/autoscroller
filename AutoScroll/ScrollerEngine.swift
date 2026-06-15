import Foundation
import UIKit

final class ScrollerEngine: ObservableObject {
    static let shared = ScrollerEngine()
    
    @Published var isRunning = false
    @Published var direction: Direction = .up
    @Published var speed: Speed = .medium
    @Published var duration: Double = 0.5
    
    var onStateChange: (() -> Void)?
    
    enum Direction: String, CaseIterable, Identifiable {
        case up, down
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }
    
    enum Speed: Double, CaseIterable, Identifiable {
        case fast = 1.0, medium = 2.5, slow = 5.0
        var id: Double { rawValue }
        var label: String {
            switch self { case .fast: "1s"; case .medium: "2.5s"; case .slow: "5s" }
        }
    }
    
    private var timer: DispatchSourceTimer?
    private let screen = UIScreen.main.bounds
    
    func toggle() { isRunning ? stop() : start() }
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        onStateChange?()
        scheduleNext()
    }
    
    func stop() {
        isRunning = false
        onStateChange?()
        timer?.cancel()
        timer = nil
    }
    
    private func scheduleNext() {
        timer?.cancel()
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "scroll.timer"))
        timer?.schedule(deadline: .now() + speed.rawValue)
        timer?.setEventHandler { [weak self] in self?.performSwipe() }
        timer?.resume()
    }
    
    private func performSwipe() {
        guard isRunning else { return }
        let w = screen.width, h = screen.height
        let mx = w * 0.5
        let ty = h * 0.3, by = h * 0.7
        
        TouchInjector.swipe(
            fromX: mx, fromY: direction == .up ? by : ty,
            toX: mx, toY: direction == .up ? ty : by,
            duration: duration
        )
        
        Thread.sleep(forTimeInterval: 0.15)
        scheduleNext()
    }
}
