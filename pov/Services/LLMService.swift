import Foundation
import UIKit
import Combine

enum LLMMode {
    /// Object tag -> poetic noun
    case textToText(tag: String, color: String)
    /// Arbitrary prompt -> direct completion (used for poetry lines)
    case textPrompt(prompt: String)
    /// Vision
    case imageToText(image: UIImage)
}

class LLMService {
    
    func generatePoeticWord(mode: LLMMode) -> AnyPublisher<String, Error> {
        switch mode {
        case .textToText(let tag, _):
            // Simple object-to-word prompt
            let prompt = "基于「\(tag)」这个物体，写一个抽象的、诗意的名词。只返回一个词，不要解释，不要标点符号。"
            return fetchQwenText(prompt: prompt)
            
        case .textPrompt(let prompt):
            // Use the prompt as-is (e.g., full poem instruction)
            return fetchQwenText(prompt: prompt)
            
        case .imageToText(let image):
            let prompt = "用3个抽象的诗意形容词描述这张图片的氛围。用逗号分隔，不要解释。"
            return fetchQwenVision(image: image, prompt: prompt)
        }
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
            "max_tokens": 50,
            "temperature": 0.9
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("❌ LLM: JSON serialization failed")
            return Fail(error: error).eraseToAnyPublisher()
        }
        
        print("📤 LLM Request: '\(prompt)'")
        
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
