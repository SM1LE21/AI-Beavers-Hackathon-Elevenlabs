import AVFoundation
import Foundation

// The fixed set of coaching lines. Each carries its live TTS text and the
// bundled MP3 used when the ElevenLabs call is unavailable.
enum VoiceLine {
    case tossArmFault
    case clean
    case test

    var text: String {
        switch self {
        case .tossArmFault: return "Heads up. Your tossing arm bent during the ball toss. Keep it straight all the way up."
        case .clean: return "Nice serve. Your tossing arm stayed straight through the toss."
        case .test: return "Voice check. Keep your tossing arm straight all the way up."
        }
    }

    var resourceName: String {
        switch self {
        case .tossArmFault: return "voice_fault"
        case .clean: return "voice_clean"
        case .test: return "voice_test"
        }
    }
}

// Speaks one short coaching line per serve via ElevenLabs, falling back to a
// pre-generated bundled MP3 when the live call fails or no key is set.
@MainActor
final class VoiceFeedback {
    private let modelID = "eleven_v3"
    private var player: AVAudioPlayer?

    func speak(_ line: VoiceLine) {
        speak(text: line.text, fallback: line)
    }

    // Speaks arbitrary text via ElevenLabs; falls back to `fallback`'s bundled MP3
    // when the live call errors or no key is set.
    func speak(text: String, fallback: VoiceLine) {
        print("VoiceFeedback: requesting TTS (\(text.count) chars, voice=\(Secrets.elevenLabsVoiceID))")
        Task { await synthesizeAndPlay(text: text, fallback: fallback) }
    }

    private func synthesizeAndPlay(text: String, fallback: VoiceLine) async {
        if !Secrets.elevenLabsAPIKey.isEmpty {
            do {
                play(try await synthesize(text))
                return
            } catch {
                print("VoiceFeedback synthesis error: \(error.localizedDescription) — using bundled audio")
            }
        }
        playBundled(fallback)
    }

    private func synthesize(_ text: String) async throws -> Data {
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(Secrets.elevenLabsVoiceID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Secrets.elevenLabsAPIKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": modelID,
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.8],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("VoiceFeedback: HTTP \(status), \(data.count) bytes")
        if status != 200 {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "VoiceFeedback",
                code: status,
                userInfo: [NSLocalizedDescriptionKey: "ElevenLabs \(status): \(detail)"]
            )
        }
        return data
    }

    private func playBundled(_ line: VoiceLine) {
        guard let url = Bundle.main.url(forResource: line.resourceName, withExtension: "mp3"),
              let audio = try? Data(contentsOf: url) else {
            print("VoiceFeedback: missing bundled audio \(line.resourceName).mp3")
            return
        }
        print("VoiceFeedback: playing bundled \(line.resourceName).mp3 (\(audio.count) bytes)")
        play(audio)
    }

    private func play(_ audio: Data) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.duckOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: audio)
            self.player = player
            let started = player.play()
            print("VoiceFeedback: playing \(audio.count) bytes, started=\(started), volume=\(AVAudioSession.sharedInstance().outputVolume)")
        } catch {
            print("VoiceFeedback playback error: \(error.localizedDescription)")
        }
    }
}
