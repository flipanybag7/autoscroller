import Foundation
import UIKit

/// Touch injection via GraphicsServices (GSEvent) — the same API AutoTouch uses.
/// No IOHIDEvent entitlements needed, just platform-application (TrollStore provides).
enum TouchInjector {
    
    // GSEvent types
    private static let kGSEventHand = 3001
    private static let kGSHandInfoTypeTouchDown: Int32 = 0
    private static let kGSHandInfoTypeTouchMoved: Int32 = 1
    private static let kGSHandInfoTypeTouchUp: Int32 = 2
    
    static func swipe(fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat, duration: TimeInterval = 0.5) {
        let steps = max(Int(duration * 60), 10)
        let interval = duration / Double(steps)
        
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = fromX + (toX - fromX) * t
            let y = fromY + (toY - fromY) * t
            let phase: Int32 = (i == steps) ? kGSHandInfoTypeTouchUp : (i == 0 ? kGSHandInfoTypeTouchDown : kGSHandInfoTypeTouchMoved)
            injectTouch(x: x, y: y, phase: phase)
            if i < steps { Thread.sleep(forTimeInterval: interval) }
        }
    }
    
    private static func injectTouch(x: CGFloat, y: CGFloat, phase: Int32) {
        // GSEventRecord with GSHandInfo
        // struct GSEventRecord { GSEventType type; GSEventTime timestamp; ... info[80] }
        // struct GSHandInfo { GSHandInfoType type; float x, y, z; ... }
        
        var record = GSEventRecord()
        record.type = 3001  // kGSEventHand
        record.timestamp = mach_absolute_time()
        record.infoSize = 40 // sizeof(GSHandInfo) on 64-bit
        
        // Write GSHandInfo into record.info
        var handInfo = GSHandInfo()
        handInfo.type = phase
        handInfo.x = Float(x)
        handInfo.y = Float(y)
        handInfo.z = 0
        handInfo.deltaX = 0
        handInfo.deltaY = 0
        handInfo.pathIndex = 1
        handInfo.pathIdentity = 2
        handInfo.pathProximity = (phase == kGSHandInfoTypeTouchUp) ? 0 : 1
        
        memcpy(&record.info, &handInfo, 40)
        
        let event = GSCreateEvent(&record)
        guard let event = event else { return }
        GSSendEvent(event, 0)
        CFRelease(event)
    }
}

// MARK: - GSEvent C types and functions

private struct GSEventRecord {
    var type: Int32 = 0        // UInt32 GSEventType
    var subtype: Int32 = 0
    var location: CGPoint = .zero
    var windowLocation: CGPoint = .zero
    var timestamp: UInt64 = 0
    var modifierFlags: UInt64 = 0
    var infoSize: UInt32 = 0
    var reserved: UInt32 = 0
    var info: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
              UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private struct GSHandInfo {
    var type: Int32 = 0       // GSHandInfoType
    var subtype: Int32 = 0
    var x: Float = 0
    var y: Float = 0
    var z: Float = 0
    var deltaX: Float = 0
    var deltaY: Float = 0
    var deltaZ: Float = 0
    var pathIndex: UInt32 = 0
    var pathIdentity: UInt32 = 0
    var pathProximity: UInt32 = 0
}

@_silgen_name("GSCreateEvent")
private func GSCreateEvent(_ record: UnsafePointer<GSEventRecord>) -> Unmanaged<AnyObject>?

@_silgen_name("GSSendEvent")
private func GSSendEvent(_ event: AnyObject, _ port: pid_t)
