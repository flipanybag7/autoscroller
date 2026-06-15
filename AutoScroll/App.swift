import SwiftUI

@main
struct AutoScrollApp: App {
    @StateObject private var engine = ScrollerEngine()
    
    var body: some Scene {
        WindowGroup {
            ContentView(engine: engine)
        }
    }
}
