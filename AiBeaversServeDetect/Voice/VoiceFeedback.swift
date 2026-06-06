import AVFoundation
import Foundation

// Speaks one short coaching line per serve via ElevenLabs text-to-speech.
@MainActor
final class VoiceFeedback {
    private let modelID = "eleven_turbo_v2_5"
    private var player: AVAudioPlayer?

    func speak(_ text: String) {
        guard !Secrets.elevenLabsAPIKey.isEmpty else {
            print("VoiceFeedback: set elevenLabsAPIKey in Secrets.swift to hear feedback.")
            return
        }
        Task { await synthesizeAndPlay(text) }
    }

    private func synthesizeAndPlay(_ text: String) async {
        do {
            let audio = try await synthesize(text)
            play(audio)
        } catch {
            print("VoiceFeedback synthesis error: \(error.localizedDescription)")
        }
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
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "VoiceFeedback",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "ElevenLabs \(http.statusCode): \(detail)"]
            )
        }
        return data
    }

    private func play(_ audio: Data) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.duckOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: audio)
            self.player = player
            player.play()
        } catch {
            print("VoiceFeedback playback error: \(error.localizedDescription)")
        }
    }
}
