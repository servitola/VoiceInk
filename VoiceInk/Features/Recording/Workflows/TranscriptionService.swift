import Foundation

struct TranscriptionRequestContext {
    /// Every language the user selected. Backends that can honour more than one (Whisper,
    /// Parakeet v3) read this; the rest use `language`.
    let languages: [String]
    /// The selection reduced to the single value single-locale backends accept. Resolved by
    /// `ModeRuntimeResolver` via `TranscriptionLanguageSupport.singleLanguage(from:for:)`.
    let language: String?
    let prompt: String?

    init(languages: [String], language: String?, prompt: String?) {
        self.languages = languages
        self.language = language
        self.prompt = prompt
    }

    init(language: String?, prompt: String?) {
        self.init(languages: language.map { [$0] } ?? [], language: language, prompt: prompt)
    }

    static var currentDefaults: TranscriptionRequestContext {
        let languages = UserDefaults.standard.selectedLanguages
        return TranscriptionRequestContext(
            languages: languages,
            language: languages.count == 1 ? languages[0] : "auto",
            prompt: WhisperPrompt.combinedPrompt(for: languages)
        )
    }

    func scoped(to model: any TranscriptionModel) -> TranscriptionRequestContext {
        guard model.provider == .whisper else {
            return TranscriptionRequestContext(languages: languages, language: language, prompt: nil)
        }

        return self
    }
}

/// A protocol defining the interface for a transcription service.
/// This allows for a unified way to handle both local and cloud-based transcription models.
protocol TranscriptionService {
    /// Transcribes the audio from a given file URL.
    ///
    /// - Parameters:
    ///   - audioURL: The URL of the audio file to transcribe.
    ///   - model: The `TranscriptionModel` to use for transcription. This provides context about the provider (local, OpenAI, etc.).
    /// - Returns: The transcribed text as a `String`.
    /// - Throws: An error if the transcription fails.
    func transcribe(audioURL: URL, model: any TranscriptionModel, context: TranscriptionRequestContext) async throws
        -> String
}

extension TranscriptionService {
    func transcribe(audioURL: URL, model: any TranscriptionModel) async throws -> String {
        let context = TranscriptionRequestContext.currentDefaults.scoped(to: model)
        return try await transcribe(audioURL: audioURL, model: model, context: context)
    }
}
