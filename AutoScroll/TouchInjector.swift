import Foundation
import UIKit

/// Injects touch events via IOKit HID (linked directly, no dlsym).
/// Requires platform-application entitlement (TrollStore provides this).
enum TouchInjector {
    
    static func swipe(fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat, duration: TimeInterval = 0.5) {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { return }
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        
        let steps = max(Int(duration * 60), 10)
        let interval = duration / Double(steps)
        
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let nx = (fromX + (toX - fromX) * t) / w
            let ny = (fromY + (toY - fromY) * t) / h
            
            let event = IOHIDEventCreateDigitizerEvent(
                kCFAllocatorDefault, 0, 3, 0, 1, 5,
                0, 0, 0, Double(nx), Double(ny), 0, 0, 0, 0
            )?.takeRetainedValue()
            
            guard let event = event else { continue }
            
            if i == steps {
                IOHIDEventSetIntegerValue(event, 720921, 0)  // touch up
            } else {
                IOHIDEventSetIntegerValue(event, 720921, 1)  // touch down
            }
            IOHIDEventSetFloatValue(event, 720937, Double(i == steps ? 3 : 1))
            
            IOHIDEventSystemClientDispatchEvent(client, event)
            if i < steps { Thread.sleep(forTimeInterval: interval) }
        }
    }
}

// MARK: - IOKit HID C functions (resolved at link time via -weak_framework IOKit)

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventSystemClientDispatchEvent")
private func IOHIDEventSystemClientDispatchEvent(_ client: AnyObject, _ event: AnyObject)

@_silgen_name("IOHIDEventCreateDigitizerEvent")
private func IOHIDEventCreateDigitizerEvent(
    _ allocator: CFAllocator?, _ timestamp: UInt64,
    _ transducer: UInt32, _ index: UInt32, _ identity: UInt32,
    _ eventMask: UInt32, _ buttonMask: UInt32,
    _ range: Double, _ touch: Double,
    _ x: Double, _ y: Double, _ z: Double,
    _ tipPressure: Double, _ twist: Double, _ options: UInt32
) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventSetIntegerValue")
private func IOHIDEventSetIntegerValue(_ event: AnyObject, _ field: Int32, _ value: Int32)

@_silgen_name("IOHIDEventSetFloatValue")
private func IOHIDEventSetFloatValue(_ event: AnyObject, _ field: Int32, _ value: Double)
