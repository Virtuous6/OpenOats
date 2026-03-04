@preconcurrency import AVFoundation
import FluidAudio
import os

/// Consumes an audio buffer stream, detects speech via Silero VAD,
/// and transcribes completed speech segments via Parakeet-TDT.
final class StreamingTranscriber: @unchecked Sendable {
    private let asrManager: AsrManager
    private let vadManager: VadManager
    private let speaker: Speaker
    private let onPartial: @Sendable (String) -> Void
    private let onFinal: @Sendable (String) -> Void
    private let log = Logger(subsystem: "com.onthespot", category: "StreamingTranscriber")

    /// Resampler from source format to 16kHz mono Float32.
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    init(
        asrManager: AsrManager,
        vadManager: VadManager,
        speaker: Speaker,
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String) -> Void
    ) {
        self.asrManager = asrManager
        self.vadManager = vadManager
        self.speaker = speaker
        self.onPartial = onPartial
        self.onFinal = onFinal
    }

    /// Main loop: reads audio buffers, runs VAD, transcribes speech segments.
    func run(stream: AsyncStream<AVAudioPCMBuffer>) async {
        var vadState = await vadManager.makeStreamState()
        var speechSamples: [Float] = []
        var isSpeaking = false

        for await buffer in stream {
            // Resample to 16kHz mono
            guard let samples = resample(buffer) else { continue }

            // Run VAD on this chunk
            do {
                let result = try await vadManager.processStreamingChunk(
                    samples,
                    state: vadState,
                    config: .default,
                    returnSeconds: true,
                    timeResolution: 2
                )
                vadState = result.state

                if let event = result.event {
                    switch event.kind {
                    case .speechStart:
                        isSpeaking = true
                        speechSamples.removeAll(keepingCapacity: true)
                        log.debug("[\(self.speaker.rawValue)] speech start")

                    case .speechEnd:
                        isSpeaking = false
                        log.debug("[\(self.speaker.rawValue)] speech end, samples=\(speechSamples.count)")

                        // Transcribe the accumulated segment
                        if speechSamples.count > 8000 { // >0.5s at 16kHz
                            let segment = speechSamples
                            speechSamples.removeAll(keepingCapacity: true)
                            await transcribeSegment(segment)
                        } else {
                            speechSamples.removeAll(keepingCapacity: true)
                        }
                    }
                }

                // Accumulate samples during speech
                if isSpeaking {
                    speechSamples.append(contentsOf: samples)

                    // Force-flush if segment gets too long (30s = 480,000 samples)
                    if speechSamples.count > 480_000 {
                        let segment = speechSamples
                        speechSamples.removeAll(keepingCapacity: true)
                        await transcribeSegment(segment)
                    }
                }
            } catch {
                log.error("VAD error: \(error.localizedDescription)")
            }
        }

        // Flush any remaining speech on stream end
        if speechSamples.count > 8000 {
            await transcribeSegment(speechSamples)
        }
    }

    private func transcribeSegment(_ samples: [Float]) async {
        do {
            let result = try await asrManager.transcribe(samples)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            log.info("[\(self.speaker.rawValue)] transcribed: \(text.prefix(80))")
            onFinal(text)
        } catch {
            log.error("ASR error: \(error.localizedDescription)")
        }
    }

    /// Resample AVAudioPCMBuffer to 16kHz mono [Float].
    private func resample(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let sourceFormat = buffer.format

        // Set up converter on first buffer (or if format changes)
        if converter == nil || converter?.inputFormat != sourceFormat {
            converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outputFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard outputFrames > 0 else { return nil }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrames
        ) else { return nil }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            log.error("Resample error: \(error.localizedDescription)")
            return nil
        }

        guard let channelData = outputBuffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(
            start: channelData[0],
            count: Int(outputBuffer.frameLength)
        ))
    }
}
