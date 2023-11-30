import SwiftUI
import AVFoundation
import Accelerate

/// An interactive waveform generated from an `AVAudioFile`.
public struct StartWaveform: View {
    @ObservedObject var generator: WaveformGenerator
    @Binding var selectedSamples: SampleRange
    @Binding var playingSamples: SampleRange
    @Binding var zoom: CGFloat
    
    private let selectedColor: Color
    private let playingColor: Color
    
    /// Creates an instance powered by the supplied generator.
    /// - Parameters:
    ///   - generator: The object that will supply waveform data.
    ///   - selectedSamples: A binding to a `SampleRange` to update with the selection chosen in the waveform.
    ///   - selectionEnabled: A binding to enable/disable selection on the waveform
    public init(
        generator: WaveformGenerator,
        selectedSamples: Binding<SampleRange>,
        playingSamples: Binding<SampleRange>,
        selectedColor: Color,
        playingColor: Color,
        zoom: Binding<CGFloat>
    ) {
        self._selectedSamples = selectedSamples
        self._playingSamples = playingSamples
        self._zoom = zoom
        self.generator = generator
        self.selectedColor = selectedColor
        self.playingColor = playingColor
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // invisible rectangle needed to register gestures that aren't on top of the waveform
                Rectangle()
                    .foregroundColor(Color(.systemBackground).opacity(0.01))
                
                Renderer(waveformData: generator.sampleData)
                    .preference(key: SizeKey.self, value: geometry.size)
                
                if !generator.sampleData.isEmpty {
                    Highlight(selectedSamples: selectedSamples)
                        .foregroundColor(selectedColor)
                        .opacity(0.5)
                    Highlight(selectedSamples: playingSamples)
                        .foregroundColor(playingColor)
                        .opacity(0.5)

                }
            }
            .padding(.bottom, 30)
        }
        .onChange(of: zoom) { newZoom  in
            zoom(amount: newZoom)
        }
        .environmentObject(generator)
        .onPreferenceChange(SizeKey.self) {
            guard generator.width != $0.width else { return }
            generator.width = $0.width
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
