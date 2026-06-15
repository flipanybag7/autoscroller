import SwiftUI

struct ContentView: View {
    @ObservedObject var engine: ScrollerEngine
    @State private var showSettings = false
    @State private var customPause: Double = 2.5
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text("AutoScroll")
                        .font(.system(size: 32, weight: .bold))
                    HStack(spacing: 6) {
                        Circle()
                            .fill(engine.isRunning ? Color.green : Color.gray)
                            .frame(width: 10, height: 10)
                        Text(engine.isRunning ? "Running" : "Stopped")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 50)
                .padding(.bottom, 30)
                
                // Big start/stop button
                Button(action: { engine.toggle() }) {
                    Text(engine.isRunning ? "STOP" : "START")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 180, height: 180)
                        .background(
                            Circle()
                                .fill(engine.isRunning ? Color.red : Color.blue)
                                .shadow(radius: 8)
                        )
                }
                .padding(.bottom, 30)
                
                // Quick info
                HStack(spacing: 24) {
                    Label(engine.direction.label, systemImage: "arrow.up.arrow.down")
                    Label(engine.speed.label, systemImage: "timer")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                Spacer()
                
                // Settings sheet button
                Button(action: { showSettings = true }) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text("Settings")
                    }
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(engine: engine, customPause: $customPause)
        }
    }
}

// MARK: - Settings sheet

struct SettingsView: View {
    @ObservedObject var engine: ScrollerEngine
    @Binding var customPause: Double
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                // Direction
                Section("Swipe Direction") {
                    Picker("Direction", selection: $engine.direction) {
                        ForEach(ScrollerEngine.Direction.allCases) { d in
                            Text(d.label).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Speed
                Section("Scroll Speed") {
                    Picker("Speed", selection: $engine.speed) {
                        ForEach(ScrollerEngine.Speed.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if engine.speed == .custom {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pause: \(String(format: "%.1f", customPause))s")
                                .font(.subheadline)
                            Slider(value: $customPause, in: 0.5...10.0, step: 0.1)
                        }
                        .onChange(of: customPause) { _ in
                            // Custom uses this value for pause
                        }
                    }
                }
                
                // Swipe duration
                Section("Swipe Duration") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(String(format: "%.2f", engine.duration))s")
                            .font(.subheadline)
                        Slider(value: $engine.duration, in: 0.1...1.5, step: 0.05)
                    }
                }
                
                // Randomization
                Section("Randomization") {
                    Toggle("Random Position", isOn: $engine.randomPosition)
                    Toggle("Random Pause Timing", isOn: $engine.randomPause)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
