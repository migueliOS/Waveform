import AVFoundation
import Accelerate

class GenerateTask {
    let audioBuffer: AVAudioPCMBuffer
    private var _isCancelled = false
    private let cancelLock = NSLock()
    private var workItems = [DispatchWorkItem]()

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
        workItems.forEach { $0.cancel() }
    }

    func resume(width: CGFloat, renderSamples: SampleRange, completion: @escaping ([SampleData]) -> Void) {
        var sampleData = [SampleData](repeating: .zero, count: Int(width))
        var tempSampleData = [SampleData?](repeating: nil, count: Int(width))
        workItems = []
        
        let group = DispatchGroup()
        let dataCollectionQueue = DispatchQueue(label: "dataCollectionQueue", attributes: .concurrent)
        
        for point in 0..<Int(width) {
            let workItem = DispatchWorkItem {
                let channels = Int(self.audioBuffer.format.channelCount)
                let totalSamples = renderSamples.upperBound - renderSamples.lowerBound
                let samplesPerPoint = max(1, totalSamples / Int(width))
                
                guard let floatChannelData = self.audioBuffer.floatChannelData else { return }
                
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
                
                dataCollectionQueue.async(flags: .barrier) {
                    tempSampleData[point] = data
                }
                
                // Check for cancellation inside the work item
                guard !self.isCancelled else { return }
            }
            
            workItems.append(workItem)
            DispatchQueue.global(qos: .userInteractive).async(group: group, execute: workItem)
        }
        
        group.notify(queue: .main) {
            if !self.isCancelled {
                for point in 0..<Int(width) {
                    if let data = tempSampleData[point] {
                        sampleData[point] = data
                    }
                }
                completion(sampleData)
            }
        }
    }
}
