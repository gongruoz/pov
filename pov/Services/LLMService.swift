import Foundation
import UIKit
import Combine

// MARK: - Vision Essence Response (JSON)

struct VisionEssenceResponse: Codable {
    let reflection: String
    let pebbles: [String]
}

// MARK: - LLM Modes

enum LLMMode {
    /// New Architecture: Image -> Reflection + 8 Pebbles (JSON)
    case visionEssence(image: UIImage)
    
    /// Context + Selected Words -> Poem line (12 words max)
    case generatePoem(context: PoeticSessionContext)
    
    /// Utility: simple text prompt
    case textPrompt(prompt: String)
}

// MARK: - LLM Service

class LLMService {
    
    private let userLanguage = "English" // TODO: Make configurable
    
    // MARK: - Public API
    
    func generate(mode: LLMMode) -> AnyPublisher<Any, Error> {
        switch mode {
        case .visionEssence(let image):
            return generateVisionEssence(image: image)
                .map { $0 as Any }
                .eraseToAnyPublisher()
            
        case .generatePoem(let context):
            return generatePoemLine(context: context)
                .map { $0 as Any }
                .eraseToAnyPublisher()
            
        case .textPrompt(let prompt):
            return fetchQwenText(prompt: prompt)
                .map { $0 as Any }
                .eraseToAnyPublisher()
        }
    }
    
    func generateVisionEssence(image: UIImage) -> AnyPublisher<VisionEssenceResponse, Error> {
        let prompt = """
        [ROLE]
        You are a whimsical poet-philosopher exploring the collective unconscious. You possess an "unfurnished eye"—seeing the raw essence of reality.

        [TASK]
        1. SEE: Look at this image. Non-literally translate what you see into subjective, spiritual, or archetypal meanings. Feel the philosophical tension and symbolism.
        2. REFLECT: Write a "poem of view" (internal monologue) in less than 50 words. Personal, intimate, sensorial.
        3. DISTILL: Condense that reflection into exactly 8 "pebbles"—simple, everyday, sensorial, archetypal, direct phrases (1-3 words each).

        [CONSTRAINTS]
        - The pebbles must be surprising yet rooted in the image.
        - Avoid abstract words like "eternity" or "love". Use concrete words like "rust", "wet glass", "bent spoon".
        - Output ONLY raw JSON. No markdown, no explanations.

        [OUTPUT FORMAT]
        {
          "reflection": "your internal monologue here...",
          "pebbles": ["phrase 1", "phrase 2", "phrase 3", "phrase 4", "phrase 5", "phrase 6", "phrase 7", "phrase 8"]
        }
        """
        
        return fetchQwenVision(image: image, prompt: prompt)
            .tryMap { [weak self] raw -> VisionEssenceResponse in
                guard let self = self else { throw URLError(.cannotDecodeRawData) }
                
                let cleaned = self.cleanJSONString(raw)
                guard let data = cleaned.data(using: .utf8) else {
                    throw URLError(.cannotDecodeRawData)
                }
                
                let decoded = try JSONDecoder().decode(VisionEssenceResponse.self, from: data)
                
                let cleanPebbles = decoded.pebbles
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                
                return VisionEssenceResponse(
                    reflection: decoded.reflection.trimmingCharacters(in: .whitespacesAndNewlines),
                    pebbles: Array(cleanPebbles.prefix(8))
                )
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Poem Generation
    
    private func generatePoemLine(context: PoeticSessionContext) -> AnyPublisher<String, Error> {
        let anchors = context.activeAnchors.joined(separator: ", ")
        let previousLines = context.formatPoemHistory()
        let isFirstLine = context.poemLines.isEmpty
        
        let prompt: String
        
        if isFirstLine {
            prompt = """
            [GOAL]
            Write the first line of a poem.
            
            [INPUT]
            - Inspiration: \(anchors)
            
            [INSTRUCTION]
            Write a poetic line. MAXIMUM 10 WORDS. Count carefully.
            Inspired by the input words.
            Style: intimate, sensorial, whimsical, experimental, intuitive, inquisitive, poetic, not cliche. surprising.
            
            [FORBIDDEN]
            - No dashes (—, -, –)
            - No quotes
            - No explanations
            - No more than 10 words
            
            Output ONLY the line.
            """
        } else {
            prompt = """
            [GOAL]
            Write a new line in this poem.
            
            [CONTEXT]
            Previous lines:
            \(previousLines)
            
            [INPUT]
            - Inspiration: \(anchors)
            
            [INSTRUCTION]
            Write ONE new line. MAXIMUM 10 WORDS. Count carefully.
            Inspired by the input words.
            Style: intimate, sensorial, whimsical, experimental, intuitive, inquisitive, poetic, not cliche. surprising.
            Maintain the rhythm.
            
            [FORBIDDEN]
            - No dashes (—, -, –)
            - No quotes
            - No explanations
            - No more than 10 words
            
            Output ONLY the line.
            """
        }
        
        return fetchQwenText(prompt: prompt)
    }
    
    // MARK: - Qwen Text API
    
    private func fetchQwenText(prompt: String) -> AnyPublisher<String, Error> {
        guard let url = URL(string: AppConfig.apiBaseURL) else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(AppConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15.0
        
        let body: [String: Any] = [
            "model": AppConfig.modelName,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 100,
            "temperature": 0.9
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .map { $0.data }
            .decode(type: OpenAIResponse.self, decoder: JSONDecoder())
            .map { $0.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "..." }
            .map { text in
                // Clean up: remove slashes, dashes, and limit length
                var clean = text
                    .replacingOccurrences(of: "/", with: ",")
                    .replacingOccurrences(of: "—", with: " ")
                    .replacingOccurrences(of: "–", with: " ")
                    .replacingOccurrences(of: " - ", with: " ")
                    .replacingOccurrences(of: "  ", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                return clean
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Qwen Vision API
    
    private func fetchQwenVision(image: UIImage, prompt: String) -> AnyPublisher<String, Error> {
        guard let url = URL(string: AppConfig.apiBaseURL) else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        
        let resizedImage = resizeImage(image, maxSize: 512)
        let base64String = resizedImage.jpegData(compressionQuality: 0.6)?.base64EncodedString() ?? ""
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(AppConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 25.0
        
        let body: [String: Any] = [
            "model": AppConfig.modelName,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64String)"]]
                    ]
                ]
            ],
            "max_tokens": 300
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .map { $0.data }
            .decode(type: OpenAIResponse.self, decoder: JSONDecoder())
            .map { $0.choices?.first?.message?.content ?? "" }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Helpers
    
    private func resizeImage(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        let size = image.size
        let ratio = min(maxSize / size.width, maxSize / size.height)
        if ratio >= 1 { return image }
        
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return resized
    }
    
    private func cleanJSONString(_ input: String) -> String {
        var json = input
        json = json.replacingOccurrences(of: "```json", with: "")
        json = json.replacingOccurrences(of: "```JSON", with: "")
        json = json.replacingOccurrences(of: "```", with: "")
        
        if let startIndex = json.firstIndex(of: "{"),
           let endIndex = json.lastIndex(of: "}") {
            json = String(json[startIndex...endIndex])
        }
        
        return json.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - OpenAI Response Models

struct OpenAIResponse: Codable {
    let id: String?
    let choices: [OpenAIChoice]?
    let error: OpenAIError?
}

struct OpenAIChoice: Codable {
    let index: Int?
    let message: OpenAIMessage?
}

struct OpenAIMessage: Codable {
    let role: String?
    let content: String?
}

struct OpenAIError: Codable {
    let message: String?
    let type: String?
    let code: String?
}
