import Foundation
import UIKit
import Combine

// MARK: - LLM Modes

enum LLMMode {
    /// Image -> Plain description (Slow Stream: describe what's visible)
    case imageToDescription(image: UIImage)
    
    /// Context -> 5 poetic word fragments ("pebbles")
    case generatePebbles(context: PoeticSessionContext, currentObject: String?)
    
    /// Selected words + context -> Poem line
    case generatePoem(context: PoeticSessionContext)
    
    /// Legacy: simple text prompt
    case textPrompt(prompt: String)
}

// MARK: - LLM Service

class LLMService {
    
    private let userLanguage = "English" // TODO: Make configurable
    
    // MARK: - Public API
    
    func generate(mode: LLMMode) -> AnyPublisher<String, Error> {
        switch mode {
        case .imageToDescription(let image):
            return generateImageDescription(image: image)
            
        case .generatePebbles(let context, let currentObject):
            return generatePebbles(context: context, currentObject: currentObject)
            
        case .generatePoem(let context):
            return generatePoemLine(context: context)
            
        case .textPrompt(let prompt):
            return fetchQwenText(prompt: prompt)
        }
    }
    
    // MARK: - Tier 1: Image to Plain Description
    
    /// Describe the image in plain detail, less than 30 words
    private func generateImageDescription(image: UIImage) -> AnyPublisher<String, Error> {
        let prompt = """
        Describe this image in plain, objective detail. Focus on what is visible: objects, colors, lighting, spatial relationships.
        Keep it under 30 words. No interpretation, no emotion, just observation.
        Output in \(userLanguage).
        """
        
        return fetchQwenVision(image: image, prompt: prompt)
    }
    
    // MARK: - Tier 2: Generate Word Pebbles
    
    /// Generate 5 diverse "pebbles" - concrete words reaching into the deep world
    private func generatePebbles(context: PoeticSessionContext, currentObject: String?) -> AnyPublisher<String, Error> {
        let objectSequence = context.formatObjectSequence()
        let visualDescription = context.latestVisualDescription ?? "unknown scene"
        let selectionHistory = context.formatSelectionHistory()
        
        let prompt = """
        [SYSTEM ROLE]
        You are a poet of the "Objectivist" school, seeing with the eyes of Williams, Bishop, and Bashō.
        You value "precision creating movement." Generate words that are "probes" reaching into the deep world.
        
        [CONTEXT]
        - Objects detected in sequence: \(objectSequence)
        - Current focus: \(currentObject ?? "ambient")
        - Scene description: \(visualDescription)
        - User has previously selected: \(selectionHistory.isEmpty ? "nothing yet" : selectionHistory)
        
        [TASK]
        Offer exactly 5 "pebbles"—words or short phrases (1-3 words each).
        
        These pebbles must:
        1. Be CONCRETE and SENSORY—the "thing itself," not abstractions like "soul" or "eternity"
        2. Be DIVERSE—cover different emotional/semantic possibilities (some warm, some cold; some near, some far; some familiar, some strange)
        3. Avoid clichés—seek the "wet black bough," the unexpected angle
        4. NO adjectives of judgment (beautiful, ugly, wonderful)
        5. Consider what this scene might mean in the collective unconscious—what associations does "\(currentObject ?? "this moment")" carry in art, literature, poetry?
        
        [OUTPUT FORMAT]
        Return exactly 5 words/phrases, one per line.
        Output in \(userLanguage).
        No numbering, no explanation, just the pebbles.
        """
        
        return fetchQwenText(prompt: prompt)
    }
    
    // MARK: - Tier 3: Generate Poem Line
    
    /// Generate a poem line based on user-selected anchors and full context
    private func generatePoemLine(context: PoeticSessionContext) -> AnyPublisher<String, Error> {
        let anchors = context.activeAnchors.joined(separator: ", ")
        let visualDescription = context.latestVisualDescription ?? ""
        let poemHistory = context.formatPoemHistory()
        let selectionPattern = context.formatSelectionHistory()
        
        let prompt = """
        [GOAL]
        You are an "unfurnished eye"—a portal for "Newness." Create a "constellation of surprise."
        
        [INPUT]
        1. THE ANCHORS (user-selected objective correlatives): \(anchors)
        2. THE CONTEXT (the weather of the moment): \(visualDescription)
        3. THE HISTORY (the river we are floating on):
        \(poemHistory.isEmpty ? "(this is the first line)" : poemHistory)
        4. USER'S SELECTION PATTERN: \(selectionPattern)
        
        [THE CRAFT]
        • JUXTAPOSE: Place the anchors side by side without explanation. Let the spark jump between them.
          Example: "The white horse / in the autumn wind."
        • THE WINDOW: Halfway through, shift the gaze. If looking in, look out. If at the small, look at the large.
          Example: "Outside, the traffic, the laborers going home."
        • THE REMAINDER: Leave something unresolved. A "residue" of uncertainty. Do not tie the package too tightly.
        • TONE: "Cool" but "permeable." Like a "clean cage for invisible fish."
        • CONTINUITY: If there are previous lines, this new line should feel like a natural continuation—the same river, different water.
        
        [OUTPUT]
        A single line of poem in \(userLanguage).
        It should feel like a "brief, buoyant verse form" that "unfastens the mind."
        No quotes, no explanation, just the line.
        """
        
        return fetchQwenText(prompt: prompt)
    }
    
    // MARK: - Qwen Text API (OpenAI Compatible)
    
    private func fetchQwenText(prompt: String) -> AnyPublisher<String, Error> {
        guard let url = URL(string: AppConfig.apiBaseURL) else {
            print("❌ LLM: Invalid URL")
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
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "max_tokens": 200,
            "temperature": 0.9
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("❌ LLM: JSON serialization failed")
            return Fail(error: error).eraseToAnyPublisher()
        }
        
        print("📤 LLM Request: '\(prompt.prefix(100))...'")
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .handleEvents(
                receiveOutput: { data, response in
                    if let httpResponse = response as? HTTPURLResponse {
                        print("📥 LLM Response Status: \(httpResponse.statusCode)")
                    }
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("📥 LLM Raw Response: \(jsonString.prefix(300))...")
                    }
                },
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("❌ LLM Network Error: \(error.localizedDescription)")
                    }
                }
            )
            .map { $0.data }
            .decode(type: OpenAIResponse.self, decoder: JSONDecoder())
            .map { response in
                let text = response.choices?.first?.message?.content?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "void"
                print("✅ LLM Parsed: '\(text)'")
                return text
            }
            .catch { error -> Just<String> in
                print("❌ LLM Parse Error: \(error)")
                return Just("echo")
            }
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    // MARK: - Qwen Vision API
    
    private func fetchQwenVision(image: UIImage, prompt: String) -> AnyPublisher<String, Error> {
        guard let url = URL(string: AppConfig.apiBaseURL) else {
            return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
        }
        
        // Resize and compress image
        let resizedImage = resizeImage(image, maxSize: 512)
        let base64String = resizedImage.jpegData(compressionQuality: 0.6)?.base64EncodedString() ?? ""
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(AppConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20.0
        
        // OpenAI Vision format
        let body: [String: Any] = [
            "model": AppConfig.modelName,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64String)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 100
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        print("📤 LLM Vision Request...")
        
        return URLSession.shared.dataTaskPublisher(for: request)
            .handleEvents(
                receiveOutput: { data, response in
                    if let httpResponse = response as? HTTPURLResponse {
                        print("📥 LLM Vision Response Status: \(httpResponse.statusCode)")
                    }
                }
            )
            .map { $0.data }
            .decode(type: OpenAIResponse.self, decoder: JSONDecoder())
            .map { response in
                return response.choices?.first?.message?.content?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "silence"
            }
            .catch { error -> Just<String> in
                print("❌ LLM Vision Error: \(error)")
                return Just("shadow")
            }
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
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
}

// MARK: - OpenAI Compatible Response Models

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
