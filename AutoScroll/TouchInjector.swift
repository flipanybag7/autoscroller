import Foundation
import UIKit

/// Injects touch events via IOHIDEvent private API on jailbroken/TrollStore devices.
enum TouchInjector {
    
    static func swipe(fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat, duration: TimeInterval = 0.5) {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        
        let steps = max(Int(duration * 60), 10)
        let interval = duration / Double(steps)
        
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = (fromX + (toX - fromX) * t) / w
            let y = (fromY + (toY - fromY) * t) / h
            injectTouch(x: x, y: y, phase: i == steps ? 3 : 1)
            if i < steps { Thread.sleep(forTimeInterval: interval) }
        }
    }
    
    // MARK: - Private
    
    private static func injectTouch(x: CGFloat, y: CGFloat, phase: Int) {
        guard let client = sharedClient else { return }
        
        let event: UnsafeMutableRawPointer? = IOHIDEventCreateDigitizerEvent(
            kCFAllocatorDefault,
            mach_absolute_time(),
            3, 0, 1, 0x01, 0, 0, 0, x, y, 0, 0, 0, 0
        )
        
        guard let event = event else { return }
        
        IOHIDEventSetIntegerValue(event, 720921, (phase != 3) ? 1 : 0)
        IOHIDEventSetFloatValue(event, 720937, Double(phase))
        IOHIDEventSystemClientDispatchEvent(client, event)
    }
    
    private static var sharedClient: UnsafeMutableRawPointer? = {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else { return nil }
        IOHIDEventSystemClientSetMatching(client, nil)
        return client
    }()
}

// MARK: - C function declarations (raw pointers)

private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> UnsafeMutableRawPointer? {
    typealias Fn = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
    guard let ptr = dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCreate"),
          let fn = unsafeBitCast(ptr, to: Optional<Fn>.self) else { return nil }
    return fn(allocator)
}

private func IOHIDEventSystemClientSetMatching(_ client: UnsafeMutableRawPointer, _ matching: CFDictionary?) {
    typealias Fn = @convention(c) (UnsafeMutableRawPointer, CFDictionary?) -> Void
    let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
    guard let ptr = dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientSetMatching"),
          let fn = unsafeBitCast(ptr, to: Optional<Fn>.self) else { return }
    fn(client, matching)
}

private func IOHIDEventSystemClientDispatchEvent(_ client: UnsafeMutableRawPointer, _ event: UnsafeMutableRawPointer) {
    typealias Fn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Void
    let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
    guard let ptr = dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientDispatchEvent"),
          let fn = unsafeBitCast(ptr, to: Optional<Fn>.self) else { return }
    fn(client, event)
}

private func IOHIDEventCreateDigitizerEvent(
    _ allocator: CFAllocator?,
    _ timestamp: UInt64,
    _ transducer: UInt32, _ index: UInt32, _ identity: UInt32,
    _ eventMask: UInt32, _ buttonMask: UInt32,
    _ range: Double, _ touch: Double,
    _ x: Double, _ y: Double, _ z: Double,
    _ tipPressure: Double, _ twist: Double, _ options: UInt32
) -> UnsafeMutableRawPointer? {
    typealias Fn = @convention(c) (
        CFAllocator?, UInt64, UInt32, UInt32, UInt32, UInt32, UInt32,
        Double, Double, Double, Double, Double, Double, Double, UInt32
    ) -> UnsafeMutableRawPointer?
    let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
    guard let ptr = dlsym(RTLD_DEFAULT, "IOHIDEventCreateDigitizerEvent"),
          let fn = unsafeBitCast(ptr, to: Optional<Fn>.self) else { return nil }
    return fn(allocator, timestamp, transducer, index, identity, eventMask,
              buttonMask, range, touch, x, y, z, tipPressure, twist, options)
}

private func IOHIDEventSetIntegerValue(_ event: UnsafeMutableRawPointer, _ field: Int32, _ value: Int) {
    typealias Fn = @convention(c) (UnsafeMutableRawPointer, Int32, Int) -> Void
    let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
    guard let ptr = dlsym(RTLD_DEFAULT, "IOHIDEventSetIntegerValue"),
          let fn = unsafeBitCast(ptr, to: Optional<Fn>.self) else { return }
    fn(event, field, value)
}

private func IOHIDEventSetFloatValue(_ event: UnsafeMutableRawPointer, _ field: Int32, _ value: Double) {
    typealias Fn = @convention(c) (UnsafeMutableRawPointer, Int32, Double) -> Void
    let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
    guard let ptr = dlsym(RTLD_DEFAULT, "IOHIDEventSetFloatValue"),
          let fn = unsafeBitCast(ptr, to: Optional<Fn>.self) else { return }
    fn(event, field, value)
}
