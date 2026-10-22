import AVFoundation

/// Worker-thread only: persistent conversion preserves fractional phase across blocks.
final class PCM48kConverter {
    enum ConversionError: Error { case invalidRate, unavailable, failed(String) }
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private let ratio: Double

    init(inputSampleRate: Double) throws {
        guard inputSampleRate.isFinite, (8000...384000).contains(inputSampleRate),
              let input = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputSampleRate, channels: 2, interleaved: true),
              let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 2, interleaved: true),
              let converter = AVAudioConverter(from: input, to: output) else { throw ConversionError.invalidRate }
        inputFormat = input; outputFormat = output; self.converter = converter
        ratio = 48000 / inputSampleRate
        converter.primeMethod = .none
    }

    func convert(interleaved source: UnsafePointer<Float>, frames: Int) throws -> [Int16] {
        guard frames > 0 else { return [] }
        guard let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(frames)) else { throw ConversionError.unavailable }
        input.frameLength = AVAudioFrameCount(frames)
        let destination = input.mutableAudioBufferList.pointee.mBuffers.mData!.assumingMemoryBound(to: Float.self)
        for i in 0..<frames * 2 { destination[i] = source[i].isFinite ? min(1,max(-1,source[i])) : 0 }
        var supplied = false
        return try render(capacity: Int(ceil(Double(frames) * ratio)) + 128) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return input
        }
    }

    func finish() throws -> [Int16] {
        try render(capacity: 4096) { _, status in status.pointee = .endOfStream; return nil }
    }

    private func render(capacity: Int, input: @escaping AVAudioConverterInputBlock) throws -> [Int16] {
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(capacity)) else { throw ConversionError.unavailable }
        var error: NSError?
        let status = converter.convert(to: output, error: &error, withInputFrom: input)
        guard status != .error else { throw ConversionError.failed(error?.localizedDescription ?? "音频格式转换失败") }
        let pointer = output.audioBufferList.pointee.mBuffers.mData!.assumingMemoryBound(to: Int16.self)
        return Array(UnsafeBufferPointer(start: pointer, count: Int(output.frameLength) * 2))
    }
}
