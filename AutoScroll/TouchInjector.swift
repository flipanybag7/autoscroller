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
        
        // Create digitizer event using known field values
        // kIOHIDDigitizerTransducerTypeFinger = 2 (index finger)
        // kIOHIDDigitizerTransducerTypeHand = 3
        let event = IOHIDEventCreateDigitizerEvent(
            kCFAllocatorDefault,
            mach_absolute_time(),
            3,      // transducer = hand (3) — most compatible
            0,      // index
            1,      // identity
            0x01,   // eventMask = kIOHIDDigitizerEventRange
            0,      // buttonMask
            0,      // range = 0
            0,      // touch = 0
            x,      // x (0..1 normalized)
            y,      // y (0..1 normalized)
            0,      // z
            0,      // tipPressure
            0,      // twist
            0       // options
        )?.takeRetainedValue()
        
        guard let event = event else { return }
        defer { CFRelease(event) }
        
        // Set touch phase
        // kIOHIDEventFieldDigitizerTouch = 720921 (1=down, 0=up)
        // kIOHIDEventFieldDigitizerPhase = 720937
        IOHIDEventSetIntegerValue(event, 720921, (phase != 3) ? 1 : 0)  // touch = 1 (contact) or 0 (release)
        IOHIDEventSetFloatValue(event, 720937, Double(phase))            // phase
        
        // Dispatch
        IOHIDEventSystemClientDispatchEvent(client, event)
    }
    
    private static var sharedClient: IOHIDEventSystemClientRef? = {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else {
            return nil
        }
        // Set matching to accept digitizer events
        IOHIDEventSystemClientSetMatching(client, nil)
        return client
    }()
}

// MARK: - C function declarations

private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<IOHIDEventSystemClientRef>? {
    // Resolved via dlsym
    typealias Fn = @convention(c) (CFAllocator?) -> Unmanaged<IOHIDEventSystemClientRef>
    let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
    guard let ptr = dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCreate"),
          let fn = unsafeBitCast(ptr, to: Optional<Fn>.self) else { return nil }
    return fn(allocator)
}

private func IOHIDEventSystemClientSetMatching(_ client: IOHIDEventSystemClientRef, _ matching: CFDictionary?) {
    typealias Fn = @convention(c) (IOHIDEventSystemClientRef, CFDictionary?) -> Void
    let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
    guard let ptr = dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientSetMatching"),
          let fn = unsafeBitCast(ptr, to: Optional<Fn>.self) else { return }
    fn(client, matching)
}

private func IOHIDEventSystemClientDispatchEvent(_ client: IOHIDEventSystemClientRef, _ event: IOHIDEventRef) {
    typealias Fn = @convention(c) (IOHIDEventSystemClientRef, IOHIDEventRef) -> Void
    let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
    guard let ptr = dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientDispatchEvent"),
          let fn = unsafeBitCast(ptr, to: Optional<Fn>.self) else { return }
    fn(client, event)
}

private func IOHIDEventCreateDigitizerEvent(
    _ allocator: CFAllocator?,
    _ timestamp: UInt64,
    _ transducerType: UInt32,
    _ index: UInt32,
    _ identity: UInt32,
    _ eventMask: UInt32,
    _ buttonMask: UInt32,
    _ range: Double,
    _ touch: Double,
    _ x: Double,
    _ y: Double,
    _ z: Double,
    _ tipPressure: Double,
    _ twist: Double,
    _ options: UInt32
) -> Unmanaged<IOHIDEventRef>? {
    typealias Fn = @convention(c) (
        CFAllocator?, UInt64, UInt32, UInt32, UInt32, UInt32, UInt32,
        Double, Double, Double, Double, Double, Double, Double, UInt32
    ) -> Unmanaged<IOHIDEventRef>?
    let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
    guard let ptr = dlsym(RTLD_DEFAULT, "IOHIDEventCreateDigitizerEvent"),
          let fn = unsafeBitCast(ptr, to: Optional<Fn>.self) else { return nil }
    return fn(allocator, timestamp, transducerType, index, identity, eventMask,
              buttonMask, range, touch, x, y, z, tipPressure, twist, options)
}

private func IOHIDEventSetIntegerValue(_ event: IOHIDEventRef, _ field: Int32, _ value: Int) {
    typealias Fn = @convention(c) (IOHIDEventRef, Int32, Int) -> Void
    let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
    guard let ptr = dlsym(RTLD_DEFAULT, "IOHIDEventSetIntegerValue"),
          let fn = unsafeBitCast(ptr, to: Optional<Fn>.self) else { return }
    fn(event, field, value)
}

private func IOHIDEventSetFloatValue(_ event: IOHIDEventRef, _ field: Int32, _ value: Double) {
    typealias Fn = @convention(c) (IOHIDEventRef, Int32, Double) -> Void
    let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
    guard let ptr = dlsym(RTLD_DEFAULT, "IOHIDEventSetFloatValue"),
          let fn = unsafeBitCast(ptr, to: Optional<Fn>.self) else { return }
    fn(event, field, value)
}

// Typealiases for opaque pointers
private typealias IOHIDEventSystemClientRef = OpaquePointer
private typealias IOHIDEventRef = OpaquePointer
