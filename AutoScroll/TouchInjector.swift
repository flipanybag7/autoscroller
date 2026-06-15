import Foundation
import UIKit

enum TouchInjector {
    
    static func swipe(fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat, duration: TimeInterval = 0.5) {
        let steps = max(Int(duration * 60), 10)
        let interval = duration / Double(steps)
        
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = fromX + (toX - fromX) * t
            let y = fromY + (toY - fromY) * t
            let phase: Int32 = i == 0 ? 0 : (i == steps ? 2 : 1)
            inject(x: Float(x), y: Float(y), phase: phase)
            if i < steps { Thread.sleep(forTimeInterval: interval) }
        }
    }
    
    private static func inject(x: Float, y: Float, phase: Int32) {
        typealias GSEventRecord = (Int32, Int32, CGFloat, CGFloat, UInt64, UInt64, UInt32, UInt32,
                                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        
        typealias GSHandInfo = (Int32, Int32, Float, Float, Float, Float, Float, Float, UInt32, UInt32, UInt32)
        
        var rec: GSEventRecord = (3001, 0, 0, 0, mach_absolute_time(), 0, 40, 0,
                                   0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
                                   0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
                                   0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
                                   0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
                                   0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
                                   0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
                                   0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
                                   0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
                                   0,0,0,0,0,0,0,0)
        
        var hand: GSHandInfo = (phase, 0, x, y, 0, 0, 0, 0, 1, 2, phase == 2 ? 0 : 1)
        
        withUnsafeMutablePointer(to: &rec.7) { dst in
            withUnsafePointer(to: &hand) { src in
                memcpy(dst, src, 44)
            }
        }
        
        let fn = _gsevent("GSCreateEvent") as GSCreateEventFn?
        let sn = _gsevent("GSSendEvent") as GSSendEventFn?
        guard let create = fn, let send = sn else { return }
        
        guard let evt = create(&rec) else { return }
        send(evt, 0)
    }
    
    private typealias GSCreateEventFn = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
    private typealias GSSendEventFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    
    private static var _handle: UnsafeMutableRawPointer?
    private static func _gsevent(_ name: String) -> UnsafeMutableRawPointer? {
        if _handle == nil {
            _handle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_NOW)
        }
        guard let h = _handle else { return nil }
        return dlsym(h, name)
    }
}
