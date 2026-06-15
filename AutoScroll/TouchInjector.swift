import Foundation
import UIKit

/// Simple touch injector that talks to WDA on localhost:8100.
/// WDA must be installed on the device (it is - TrollStore).
enum TouchInjector {
    
    private static let baseURL = "http://127.0.0.1:8100"
    private static var sessionId: String?
    
    static func swipe(fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat, duration: TimeInterval = 0.5) {
        ensureSession()
        guard let sid = sessionId else { return }
        
        let body = """
        {"fromX":\(Int(fromX)),"fromY":\(Int(fromY)),"toX":\(Int(toX)),"toY":\(Int(toY)),"duration":\(duration)}
        """
        _ = post("/session/\(sid)/wda/dragfromtoforduration", body: body)
    }
    
    private static func ensureSession() {
        if sessionId != nil { return }
        
        // Check if WDA is alive
        if let status = get("/status"), status.contains("sessionId") {
            if let range = status.range(of: "\"sessionId\":\"") {
                let start = status.index(range.upperBound, offsetBy: 0)
                if let end = status[start...].firstIndex(of: "\"") {
                    sessionId = String(status[start..<end])
                    return
                }
            }
        }
        
        // Start new session
        let body = "{\"capabilities\":{\"alwaysMatch\":{}}}"
        if let resp = post("/session", body: body),
           let range = resp.range(of: "\"sessionId\":\"") {
            let start = resp.index(range.upperBound, offsetBy: 0)
            if let end = resp[start...].firstIndex(of: "\"") {
                sessionId = String(resp[start..<end])
                return
            }
        }
        
        // WDA might not be running - try to launch it
        launchWDA()
    }
    
    private static func launchWDA() {
        let bundleId = "com.facebook.WebDriverAgentRunner.xctrunner"
        
        // Try opening WDA via URL scheme or private API
        let workspace = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type
        let ws = workspace?.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue()
        _ = ws?.perform(NSSelectorFromString("openApplicationWithBundleID:"), with: bundleId)
        
        // Wait for WDA to start
        for _ in 0..<30 {
            Thread.sleep(forTimeInterval: 0.5)
            if let _ = get("/status") { break }
        }
        
        // Try creating session again
        let body = "{\"capabilities\":{\"alwaysMatch\":{}}}"
        if let resp = post("/session", body: body),
           let range = resp.range(of: "\"sessionId\":\"") {
            let start = resp.index(range.upperBound, offsetBy: 0)
            if let end = resp[start...].firstIndex(of: "\"") {
                sessionId = String(resp[start..<end])
            }
        }
    }
    
    private static func get(_ path: String) -> String? {
        return request("GET", path, body: nil)
    }
    
    private static func post(_ path: String, body: String) -> String? {
        return request("POST", path, body: body)
    }
    
    private static func request(_ method: String, _ path: String, body: String?) -> String? {
        let url = URL(string: "\(baseURL)\(path)")!
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = body {
            req.httpBody = body.data(using: .utf8)
        }
        
        let sem = DispatchSemaphore(value: 0)
        var result: String?
        
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data = data {
                result = String(data: data, encoding: .utf8)
            }
            sem.signal()
        }.resume()
        
        _ = sem.wait(timeout: .now() + 5)
        return result
    }
}
