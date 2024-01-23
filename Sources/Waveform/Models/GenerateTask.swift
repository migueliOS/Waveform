import AVFoundation
import Accelerate

class GenerateTask {
    let audioBuffer: AVAudioPCMBuffer
    private var _isCancelled = false
    private let cancelLock = NSLock()
    
    init(audioBuffer: AVAudioPCMBuffer) {
        self.audioBuffer = audioBuffer
    }
    
    var isCancelled: Bool {
        get {
            cancelLock.lock()
            defer { cancelLock.unlock() }
            return _isCancelled
        }
        set {
            cancelLock.lock()
            _isCancelled = newValue
            cancelLock.unlock()
        }
    }
    
    func cancel() {
        isCancelled = true
    }
    
    func resume(width: CGFloat, renderSamples: SampleRange, completion: @escaping ([SampleData]) -> Void) {
        var sampleData = [SampleData](repeating: .zero, count: Int(width))
        
        DispatchQueue.global(qos: .userInteractive).async {
            let channels = Int(self.audioBuffer.format.channelCount)
            let totalSamples = renderSamples.upperBound - renderSamples.lowerBound
            let samplesPerPoint = max(1, totalSamples / Int(width))
            
            guard let floatChannelData = self.audioBuffer.floatChannelData else { return }
            
            DispatchQueue.concurrentPerform(iterations: Int(width)) { point in
                // don't begin work if the task has been cancelled
                guard !self.isCancelled else { return }
                
                let startIdx = renderSamples.lowerBound + (point * samplesPerPoint)
                let endIdx = min(startIdx + samplesPerPoint, renderSamples.upperBound)
                let validLength = vDSP_Length(max(0, endIdx - startIdx))
                
                var data: SampleData = .zero
                for channel in 0..<channels {
                    let pointer = floatChannelData[channel].advanced(by: startIdx)
                    let stride = vDSP_Stride(self.audioBuffer.stride)
                    
                    var value: Float = 0
                    
                    vDSP_minv(pointer, stride, &value, validLength)
                    data.min = min(value, data.min)
                    
                    vDSP_maxv(pointer, stride, &value, validLength)
                    data.max = max(value, data.max)
                }
                
                // sync to hold completion handler until all iterations are complete
                DispatchQueue.main.sync { sampleData[point] = data }
            }
            
            DispatchQueue.main.async {
                guard !self.isCancelled else { return }
                completion(sampleData)
            }
        }
    }
}
