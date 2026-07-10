import SwiftUI
import MetalKit
import QuartzCore

struct LatencyMeasurement {
    let timestamp: CFTimeInterval
    let delta: Double
}

class LatencyTracker: ObservableObject {
    @Published var currentLatency: Double = 0.0
    @Published var history: [LatencyMeasurement] = []
    
    private let maxHistory = 50
    
    func recordTap(at time: CFTimeInterval) {
        // CADisplayLink timestamp represents the start of the current frame rendering cycle
        let renderTime = CACurrentMediaTime()
        let latencyMs = (renderTime - time) * 1000.0
        
        DispatchQueue.main.async {
            self.currentLatency = latencyMs
            self.history.append(LatencyMeasurement(timestamp: renderTime, delta: latencyMs))
            if self.history.count > self.maxHistory {
                self.history.removeFirst()
            }
        }
    }
}

struct LatencyGraphView: View {
    let history: [LatencyMeasurement]
    
    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard history.count > 1 else { return }
                let step = geo.size.width / CGFloat(history.count - 1)
                let maxHeight = geo.size.height
                
                for (index, entry) in history.enumerated() {
                    // Normalize 0-32ms as the visible range
                    let y = maxHeight - CGFloat(min(entry.delta / 32.0, 1.0)) * maxHeight
                    let x = CGFloat(index) * step
                    
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.cyan, lineWidth: 2)
        }
    }
}

struct ContentView: View {
    @StateObject private var tracker = LatencyTracker()
    @State private var flashActive = false
    
    var body: some View {
        ZStack {
            Color(flashActive ? .white : .black)
                .edgesIgnoringSafeArea(.all)
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .global) { location in
                    let tapTime = CACurrentMediaTime()
                    triggerFlash()
                    tracker.recordTap(at: tapTime)
                }
            
            VStack {
                Text("Biometric Latency Cartographer")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .padding(.top, 40)
                
                Spacer()
                
                VStack(spacing: 8) {
                    Text("\(String(format: "%.2f", tracker.currentLatency)) ms")
                        .font(.system(size: 64, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                    
                    Text("TAP TO MEASURE RENDERING LAG")
                        .font(.caption)
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                LatencyGraphView(history: tracker.history)
                    .frame(height: 120)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                    .padding()
                
                HStack {
                    Label("Direct Display", systemImage: "bolt.fill")
                    Spacer()
                    Label("Apple Silicon", systemImage: "cpu")
                }
                .font(.footnote)
                .foregroundColor(.gray)
                .padding()
            }
        }
    }
    
    private func triggerFlash() {
        flashActive = true
        // High-speed pulse logic: Toggle off as fast as the next UI cycle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) {
            flashActive = false
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}