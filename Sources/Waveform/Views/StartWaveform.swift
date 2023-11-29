import SwiftUI
import AVFoundation
import Accelerate

/// An interactive waveform generated from an `AVAudioFile`.
public struct StartWaveform: View {
    @ObservedObject var generator: WaveformGenerator
    
    @State private var zoomGestureValue: CGFloat = 1
    @State private var panGestureValue: CGFloat = 0
    
    @Binding var startSample: Int
    
    // Computed property for selectedSamples
    private var selectedSamples: SampleRange {
        startSample..<Int(generator.audioBuffer.frameLength)
    }
    
    public init(generator: WaveformGenerator, startSample: Binding<Int>) {
        self.generator = generator
        self._startSample = startSample
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .foregroundColor(Color(.systemBackground).opacity(0.01))
                 
                Renderer(waveformData: generator.sampleData)
                    .preference(key: SizeKey.self, value: geometry.size)
                
                // Use the computed selectedSamples here
                Highlight(selectedSamples: selectedSamples)
                    .foregroundColor(.accentColor)
                    .opacity(0.7)
            }
            .padding(.bottom, 30)
        }
        .gesture(SimultaneousGesture(zoom, pan))
        .environmentObject(generator)
        .onPreferenceChange(SizeKey.self) {
            guard generator.width != $0.width else { return }
            generator.width = $0.width
        }
    }
    
    var zoom: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom(amount: value / zoomGestureValue)
                zoomGestureValue = value
            }
            .onEnded { value in
                zoom(amount: value / zoomGestureValue)
                zoomGestureValue = 1
            }
    }
    
    var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                pan(offset: value.translation.width - panGestureValue)
                panGestureValue = value.translation.width
            }
            .onEnded { value in
                pan(offset: value.translation.width - panGestureValue)
                panGestureValue = 0
            }
    }
    
    func zoom(amount: CGFloat) {
        let count = generator.renderSamples.count
        let newCount = CGFloat(count) / amount
        let delta = (count - Int(newCount)) / 2
        let renderStartSample = max(0, generator.renderSamples.lowerBound + delta)
        let renderEndSample = min(generator.renderSamples.upperBound - delta, Int(generator.audioBuffer.frameLength))
        generator.renderSamples = renderStartSample..<renderEndSample
    }
    
    func pan(offset: CGFloat) {
        let count = generator.renderSamples.count
        var startSample = generator.sample(generator.renderSamples.lowerBound, with: offset)
        var endSample = startSample + count
        
        if startSample < 0 {
            startSample = 0
            endSample = generator.renderSamples.count
        } else if endSample > Int(generator.audioBuffer.frameLength) {
            endSample = Int(generator.audioBuffer.frameLength)
            startSample = endSample - generator.renderSamples.count
        }
        
        generator.renderSamples = startSample..<endSample
    }
}
