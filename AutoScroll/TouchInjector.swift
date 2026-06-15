import Foundation
import UIKit

/// Injects touch events via private IOHIDEvent API.
/// Only works on jailbroken / TrollStore devices with platform-application entitlement.
enum TouchInjector {
    
    // MARK: - Public API
    
    /// Perform a swipe from (fromX, fromY) to (toX, toY) in screen points.
    /// - Parameters:
    ///   - fromX, fromY: start position (UIKit points, 0,0 = top-left)
    ///   - toX, toY: end position
    ///   - duration: total swipe time in seconds
    static func swipe(fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat, duration: TimeInterval = 0.5) {
        let steps = max(Int(duration * 60), 10)
        let interval = duration / Double(steps)
        
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = fromX + (toX - fromX) * t
            let y = fromY + (toY - fromY) * t
            let phase: Int = (i == steps) ? 3 : 1   // 1 = touch, 3 = end
            inject(x: x, y: y, phase: phase)
            if i < steps { Thread.sleep(forTimeInterval: interval) }
        }
    }
    
    /// Tap at a point.
    static func tap(x: CGFloat, y: CGFloat) {
        inject(x: x, y: y, phase: 1)
        Thread.sleep(forTimeInterval: 0.05)
        inject(x: x, y: y, phase: 3)
    }
    
    // MARK: - Private
    
    private static func inject(x: CGFloat, y: CGFloat, phase: Int) {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        let nx = max(0, min(1, x / w))
        let ny = max(0, min(1, y / h))
        
        guard let event = _createDigitizer(nx, ny, phase)?.takeRetainedValue() else { return }
        _dispatchDigitizer(event)
    }
    
    // MARK: - IOHIDEvent C bridging
    
    private static func _createDigitizer(_ x: CGFloat, _ y: CGFloat, _ phase: Int) -> Unmanaged<CFTypeRef>? {
        // Resolve symbols from IOKit
        typealias CreateFn = @convention(c) (
            CFAllocator?,           // allocator
            UInt64,                 // timestamp (AbsoluteTime)
            Int32,                  // transducerType (0x03 = finger)
            Int32,                  // index
            UInt32,                 // identity
            Int32,                  // eventMask
            Int32,                  // buttonMask
            Double,                 // range
            Double,                 // touch
            Double,                 // x (normalized 0..1)
            Double,                 // y (normalized 0..1)
            Double,                 // z
            Double,                 // tipPressure
            Double,                 // twist
            UInt32                  // options
        ) -> Unmanaged<CFTypeRef>?
        
        typealias SetIntFn = @convention(c) (CFTypeRef, Int32, Int32) -> Void
        
        let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)!
        
        guard let createFn = _symbol("IOHIDEventCreateDigitizerEvent", from: RTLD_DEFAULT)
                .map({ unsafeBitCast($0, to: CreateFn.self) }),
              let setIntFn = _symbol("IOHIDEventSetIntegerValue", from: RTLD_DEFAULT)
                .map({ unsafeBitCast($0, to: SetIntFn.self) })
        else { return nil }
        
        let event = createFn(
            nil,                    // allocator
            0,                      // timestamp (kernel fills it)
            0x03,                   // kIOHIDTransducerTypeFinger
            0,                      // index
            2,                      // identity
            5,                      // eventMask
            0,                      // buttonMask
            0,                      // range
            0,                      // touch
            Double(x),              // x
            Double(y),              // y
            0,                      // z
            0,                      // tipPressure
            0,                      // twist
            0                       // options
        )
        
        guard let event = event else { return nil }
        
        // kIOHIDEventFieldDigitizerPhase = 720937
        setIntFn(event.takeUnretainedValue(), 720937, Int32(phase))
        
        return event
    }
    
    private static func _dispatchDigitizer(_ event: CFTypeRef) {
        typealias DispatchFn = @convention(c) (CFTypeRef?, CFTypeRef?) -> Void
        let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)!
        
        // Create the system client once and reuse
        let client: CFTypeRef? = _sharedEventSystemClient()
        
        guard let dispatchFn = _symbol("IOHIDEventSystemClientDispatchEvent", from: RTLD_DEFAULT)
                .map({ unsafeBitCast($0, to: DispatchFn.self) })
        else { return }
        
        dispatchFn(client, event.takeUnretainedValue())
    }
    
    private static var _clientCache: Unmanaged<CFTypeRef>?
    
    private static func _sharedEventSystemClient() -> CFTypeRef? {
        if let cached = _clientCache { return cached.takeUnretainedValue() }
        
        typealias CreateClientFn = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
        let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)!
        
        guard let fn = _symbol("IOHIDEventSystemClientCreate", from: RTLD_DEFAULT)
                .map({ unsafeBitCast($0, to: CreateClientFn.self) }),
              let client = fn(nil)
        else { return nil }
        
        _clientCache = client
        return client.takeUnretainedValue()
    }
    
    private static func _symbol(_ name: String, from handle: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
        return dlsym(handle, name)
    }
}
