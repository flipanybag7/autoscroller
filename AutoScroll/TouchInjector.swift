import Foundation
import UIKit

/// Touch injection via GraphicsServices GSEvent API.
/// Loaded at runtime via dlopen — same technique AutoTouch uses.
enum TouchInjector {
    
    private static var gsHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_NOW)
    }()
    
    static func swipe(fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat, duration: TimeInterval = 0.5) {
        guard let create = _fn("GSCreateEvent", as: GSCreateEventFn.self),
              let send = _fn("GSSendEvent", as: GSSendEventFn.self) else { return }
        
        let steps = max(Int(duration * 60), 10)
        let interval = duration / Double(steps)
        
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = Float(fromX + (toX - fromX) * t)
            let y = Float(fromY + (toY - fromY) * t)
            let phase: Int32 = i == 0 ? 0 : (i == steps ? 2 : 1)
            
            // GSEventRecord + GSHandInfo
            var record = _makeRecord(type: 3001, x: x, y: y, phase: phase)
            var hand = _makeHand(phase: phase, x: x, y: y)
            
            withUnsafeMutablePointer(to: &record.8) { dst in
                withUnsafePointer(to: &hand) { src in
                    memcpy(dst, src, 48)
                }
            }
            
            if let evt = create(&record) {
                send(evt, 0)
            }
            if i < steps { Thread.sleep(forTimeInterval: interval) }
        }
    }
    
    // MARK: - GSEvent helpers
    
    private typealias GSEventRecord = (Int32, Int32, CGFloat, CGFloat, UInt64, UInt64, UInt32, UInt32,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    
    private typealias GSHandInfo = (Int32, Int32, Float, Float, Float, Float, Float, Float, UInt32, UInt32, UInt32, Float)
    private typealias GSCreateEventFn = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
    private typealias GSSendEventFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    
    private static func _fn<T>(_ name: String, as: T.Type) -> T? {
        guard let h = gsHandle else { return nil }
        guard let ptr = dlsym(h, name) else { return nil }
        return unsafeBitCast(ptr, to: T.self)
    }
    
    private static func _makeRecord(type: Int32, x: Float, y: Float, phase: Int32) -> GSEventRecord {
        (type, 0, 0, 0, mach_absolute_time(), 0, 48, 0,
         0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
         0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
         0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
         0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
         0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
         0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
         0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
         0,0,0,0,0,0,0,0)
    }
    
    private static func _makeHand(phase: Int32, x: Float, y: Float) -> GSHandInfo {
        (phase, 0, x, y, 0, 0, 0, 0, 1, 2, phase == 2 ? 0 : 1, 0)
    }
}
