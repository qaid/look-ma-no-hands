import Foundation

/// Service for communicating with the local Ollama API
/// Used for AI-powered text formatting
class OllamaService {
    
    // MARK: - Configuration
    
    /// Base URL for the Ollama API
    private let baseURL = "http://localhost:11434"
    
    /// The model to use for formatting
    var modelName: String
    
    /// URL session for HTTP requests
    private let session = URLSession.shared
    
    // MARK: - Initialization
    
    init(modelName: String = "qwen3:8b") {
        self.modelName = modelName
    }
    
    // MARK: - Connection Check
    
    /// Check if Ollama is running and accessible
    /// - Returns: True if Ollama is available
    func isAvailable() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            return false
        }
        
        do {
            let (_, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            print("OllamaService: Connection check failed - \(error)")
            return false
        }
    }
    
    /// Get list of available models
    /// - Returns: Array of model names
    func listModels() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw OllamaError.invalidURL
        }
        
        let (data, _) = try await session.data(from: url)
        
        struct TagsResponse: Codable {
            struct Model: Codable {
                let name: String
            }
            let models: [Model]
        }
        
        let response = try JSONDecoder().decode(TagsResponse.self, from: data)
        return response.models.map { $0.name }
    }
    
    // MARK: - Text Formatting
    
    /// Format transcribed text using the local LLM
    /// - Parameter text: Raw transcribed text
    /// - Returns: Formatted text
    func formatText(_ text: String) async throws -> String {
        let prompt = buildFormattingPrompt(for: text)
        return try await generate(prompt: prompt)
    }
    
    /// Generate text from a prompt
    /// - Parameter prompt: The prompt to send to the model
    /// - Returns: Generated text
    func generate(prompt: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw OllamaError.invalidURL
        }
        
        // Build request body
        let requestBody: [String: Any] = [
            "model": modelName,
            "prompt": prompt,
            "stream": false
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("OllamaService: Sending request to \(modelName)...")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed
        }
        
        // Parse response
        struct GenerateResponse: Codable {
            let response: String
        }
        
        let generateResponse = try JSONDecoder().decode(GenerateResponse.self, from: data)
        
        print("OllamaService: Received response")
        
        return generateResponse.response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Prompt Building
    
    /// Build a formatting prompt based on the content
    private func buildFormattingPrompt(for text: String) -> String {
        // Detect content type and build appropriate prompt
        let contentType = detectContentType(text)
        
        let baseInstructions = """
        You are a text formatting assistant. Your job is to take raw dictated text and format it properly.
        
        Rules:
        - Add appropriate punctuation (periods, commas, question marks)
        - Fix capitalization
        - Add paragraph breaks where appropriate
        - Do NOT change the meaning or add new content
        - Do NOT add greetings or sign-offs unless they're in the original
        - Return ONLY the formatted text, no explanations
        """
        
        let typeSpecificInstructions: String
        switch contentType {
        case .email:
            typeSpecificInstructions = """
            This appears to be an email. Format it as a professional email with:
            - Greeting on its own line (if present)
            - Body paragraphs separated by blank lines
            - Closing on its own line (if present)
            """
        case .list:
            typeSpecificInstructions = """
            This appears to contain a list. Format items clearly, either as:
            - Bullet points if it's a list of items
            - Numbered list if it's sequential steps
            """
        case .note:
            typeSpecificInstructions = """
            This is a short note. Keep it concise and properly punctuated.
            """
        case .general:
            typeSpecificInstructions = """
            Format this as general text with proper sentences and paragraphs.
            """
        }
        
        return """
        \(baseInstructions)
        
        \(typeSpecificInstructions)
        
        Raw dictated text:
        \(text)
        
        Formatted text:
        """
    }
    
    /// Detect what type of content the text appears to be
    private func detectContentType(_ text: String) -> ContentType {
        let lowercased = text.lowercased()
        
        // Email indicators
        if lowercased.contains("hey ") || lowercased.contains("hi ") ||
           lowercased.contains("dear ") || lowercased.contains("thanks") ||
           lowercased.contains("let me know") || lowercased.contains("follow up") {
            return .email
        }
        
        // List indicators
        if lowercased.contains("first") && lowercased.contains("second") ||
           lowercased.contains("one ") && lowercased.contains("two ") ||
           lowercased.contains("remember to") || lowercased.contains("need to") {
            return .list
        }
        
        // Short notes
        if text.count < 100 {
            return .note
        }
        
        return .general
    }
}

// MARK: - Supporting Types

enum ContentType {
    case email
    case list
    case note
    case general
}

enum OllamaError: LocalizedError {
    case invalidURL
    case requestFailed
    case notAvailable
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Ollama API URL"
        case .requestFailed:
            return "Ollama request failed. Make sure Ollama is running."
        case .notAvailable:
            return "Ollama is not available. Please start Ollama first."
        }
    }
}
