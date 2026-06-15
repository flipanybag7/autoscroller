import Foundation

/// Touch injection via GraphicsServices GSEvent API (dlopen at runtime).
enum TouchInjector {
    
    static func swipe(fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat, duration: TimeInterval = 0.5) {
        guard let gs = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_NOW) else { return }
        guard let create = dlsym(gs, "GSCreateEvent").map({ unsafeBitCast($0, to: (@convention(c)(UnsafeRawPointer)->UnsafeMutableRawPointer?).self) }) else { return }
        guard let send = dlsym(gs, "GSSendEvent").map({ unsafeBitCast($0, to: (@convention(c)(UnsafeMutableRawPointer, Int32)->Void).self) }) else { return }
        
        let steps = max(Int(duration * 60), 10)
        let interval = duration / Double(steps)
        
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = Float(fromX + (toX - fromX) * t)
            let y = Float(fromY + (toY - fromY) * t)
            let phase: Int32 = i == 0 ? 0 : (i == steps ? 2 : 1)
            
            // Build GSEventRecord (type, sub, locX, locY, winLocX, winLocY, tsHi, tsLo, flags, modifierFlags, infoSize, subtype, then info bytes)
            // info = GSHandInfo(phase, sub, x, y, z, dx, dy, dz, pathIdx, pathIdentity, pathProximity, pressure)
            var record = Data(count: 200)
            record.withUnsafeMutableBytes { r in
                let p = r.baseAddress!.assumingMemoryBound(to: UInt8.self)
                // GSEventRecord header
                var off = 0
                func w32(_ v: Int32) { withUnsafeBytes(of: v.littleEndian) { memcpy(p + off, $0.baseAddress!, 4) }; off += 4 }
                func w64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { memcpy(p + off, $0.baseAddress!, 8) }; off += 8 }
                func wf(_ v: Float) { withUnsafeBytes(of: v) { memcpy(p + off, $0.baseAddress!, 4) }; off += 4 }
                func wu32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { memcpy(p + off, $0.baseAddress!, 4) }; off += 4 }
                
                w32(3001)       // type = kGSEventHand
                w32(0)          // subtype
                wf(0); wf(0)    // location
                wf(0); wf(0)    // windowLocation
                w64(mach_absolute_time()) // timestamp
                w64(0)          // modifierFlags
                wu32(44)        // infoSize (GSHandInfo size)
                wu32(0)         // reserved
                // GSHandInfo
                w32(phase)      // type (0=down, 1=move, 2=up)
                w32(0)          // subtype
                wf(x); wf(y); wf(0)     // x, y, z
                wf(0); wf(0); wf(0)     // dx, dy, dz
                wu32(1)         // pathIndex
                wu32(2)         // pathIdentity
                wu32(phase == 2 ? 0 : 1)  // pathProximity
                wf(0)           // pressure
            }
            
            var rec = record
            rec.withUnsafeMutableBytes { r in
                guard let evt = create(r.baseAddress!) else { return }
                send(evt, 0)
            }
            if i < steps { Thread.sleep(forTimeInterval: interval) }
        }
    }
}
