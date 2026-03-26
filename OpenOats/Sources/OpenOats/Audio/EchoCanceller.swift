@preconcurrency import AVFoundation
import DTLNAecCoreML
import DTLNAec256
import os

private let aecLog = Logger(subsystem: "com.openoats", category: "EchoCanceller")

/// Neural echo cancellation via DTLN-AEC CoreML.
///
/// Wraps `DTLNAecEchoProcessor` with automatic resampling from any input format
/// to the required 16 kHz mono Float32. Feed system audio via `feedSystemAudio(_:)`
/// and process mic audio via `processMicAudio(_:)` — returns an echo-cancelled buffer
/// at 16 kHz mono that the transcriber can consume directly (fast path).
///
/// Thread safety: all public methods are internally synchronized via the underlying
/// processor's `os_unfair_lock`. Safe to call from different dispatch queues.
final class EchoCanceller: @unchecked Sendable {
    private let processor = DTLNAecEchoProcessor(modelSize: .medium)
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    /// Lazily created resamplers — one per source format.
    private var sysConverter: AVAudioConverter?
    private var sysSourceRate: Double = 0
    private var micConverter: AVAudioConverter?
    private var micSourceRate: Double = 0

    var isInitialized: Bool { processor.isInitialized }

    /// Load CoreML models asynchronously. Call once before processing.
    func loadModels() async throws {
        try await processor.loadModelsAsync(from: DTLNAec256.bundle)
        processor.resetStates()
        aecLog.info("DTLN-AEC models loaded (medium, 256 units)")
    }

    // MARK: - Processing

    /// Feed system (far-end / speaker) audio as echo reference.
    /// Call this for every system audio buffer — does not modify the buffer.
    func feedSystemAudio(_ buffer: AVAudioPCMBuffer) {
        let samples = downsample(buffer, converter: &sysConverter, cachedRate: &sysSourceRate)
        guard !samples.isEmpty else { return }
        processor.feedFarEnd(samples)
    }

    /// Process mic (near-end) audio through echo cancellation.
    /// Returns a new `AVAudioPCMBuffer` at 16 kHz mono Float32 with echo removed.
    /// Returns `nil` if the processor has no output yet (internal buffering).
    func processMicAudio(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let samples = downsample(buffer, converter: &micConverter, cachedRate: &micSourceRate)
        guard !samples.isEmpty else { return nil }

        let cleaned = processor.processNearEnd(samples)
        guard !cleaned.isEmpty else { return nil }

        return makeBuffer(from: cleaned)
    }

    /// Drain any remaining buffered samples at end of recording.
    func flush() -> AVAudioPCMBuffer? {
        let remaining = processor.flush()
        guard !remaining.isEmpty else { return nil }
        return makeBuffer(from: remaining)
    }

    /// Reset internal LSTM state for a new recording session.
    func reset() {
        processor.resetStates()
        sysConverter = nil
        micConverter = nil
        sysSourceRate = 0
        micSourceRate = 0
        aecLog.info("DTLN-AEC state reset")
    }

    // MARK: - Resampling

    private func downsample(
        _ buffer: AVAudioPCMBuffer,
        converter: inout AVAudioConverter?,
        cachedRate: inout Double
    ) -> [Float] {
        let fmt = buffer.format
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return [] }

        // Fast path: already 16 kHz mono Float32
        if fmt.sampleRate == 16000 && fmt.channelCount == 1 && fmt.commonFormat == .pcmFormatFloat32 {
            return extractFloat32(buffer)
        }

        // Mono downmix if multi-channel
        let monoBuffer: AVAudioPCMBuffer
        if fmt.channelCount > 1 {
            guard let mixed = downmixToMono(buffer) else { return [] }
            monoBuffer = mixed
        } else {
            monoBuffer = buffer
        }

        // Resample to 16 kHz
        let sourceRate = monoBuffer.format.sampleRate
        if sourceRate != cachedRate || converter == nil {
            let monoSourceFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sourceRate,
                channels: 1,
                interleaved: false
            )!
            converter = AVAudioConverter(from: monoSourceFormat, to: targetFormat)
            cachedRate = sourceRate
        }

        guard let conv = converter else { return extractFloat32(monoBuffer) }

        let ratio = 16000.0 / sourceRate
        let outputFrames = AVAudioFrameCount(Double(monoBuffer.frameLength) * ratio) + 16
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrames) else {
            return []
        }

        var error: NSError?
        nonisolated(unsafe) var consumed = false
        conv.convert(to: outBuf, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return monoBuffer
        }

        if let error {
            aecLog.error("Resample failed: \(error.localizedDescription)")
            return []
        }

        return extractFloat32(outBuf)
    }

    private func downmixToMono(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let src = buffer.floatChannelData else { return nil }
        let frameCount = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: buffer.format.sampleRate,
            channels: 1,
            interleaved: false
        )!
        guard let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameCapacity),
              let dst = mono.floatChannelData?[0] else { return nil }
        mono.frameLength = buffer.frameLength

        let scale = 1.0 / Float(channels)
        for i in 0..<frameCount {
            var sum: Float = 0
            for ch in 0..<channels { sum += src[ch][i] }
            dst[i] = sum * scale
        }
        return mono
    }

    // MARK: - Buffer helpers

    private func extractFloat32(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
    }

    private func makeBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(samples.count)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount),
              let dst = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount
        samples.withUnsafeBufferPointer { src in
            dst.update(from: src.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
