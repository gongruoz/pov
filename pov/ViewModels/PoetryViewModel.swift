import Foundation
import Combine

struct PoemLine: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let timestamp: Date
}

class PoetryViewModel: ObservableObject {
    // Captured words (selected by user)
    @Published var capturedWords: [String] = []
    
    // Generated poem lines
    @Published var poemLines: [PoemLine] = []
    
    // Current line being typed (typewriter effect)
    @Published var currentTypingText: String = ""
    @Published var isTyping: Bool = false
    
    private let llmService = LLMService()
    private var cancellables = Set<AnyCancellable>()
    private var typingTimer: Timer?
    
    // Called when user captures (selects) a word
    func captureWord(_ word: String) {
        guard !capturedWords.contains(word) else { return }
        
        capturedWords.append(word)
        print("📝 Poetry: Captured '\(word)', total: \(capturedWords.count)")
        
        // Generate a new poem line based on all captured words
        generatePoemLine(focusWord: word)
    }
    
    // Called when user uncaptures a word
    func uncaptureWord(_ word: String) {
        capturedWords.removeAll { $0 == word }
        print("📝 Poetry: Removed '\(word)', total: \(capturedWords.count)")
    }
    
    private func generatePoemLine(focusWord: String) {
        let context = capturedWords.joined(separator: ", ")
        let prompt = "你是一位意识流诗人。基于这些词汇线索: \(context)。用新词 \(focusWord) 写一句简短的现代诗作为内心独白。要求: 一句话, 不超过15个字, 意象抽象, 有诗意。只返回诗句本身。"
        
        print("🎭 Generating poem for: '\(focusWord)'")
        
        // Use textPrompt to avoid double-wrapping the poem instruction
        llmService.generatePoeticWord(mode: .textPrompt(prompt: prompt))
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("❌ Poetry generation error: \(error)")
                }
            }, receiveValue: { [weak self] line in
                let cleanLine = line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "\u{201C}", with: "")
                    .replacingOccurrences(of: "\u{201D}", with: "")
                
                print("🎭 Generated: '\(cleanLine)'")
                self?.addPoemLineWithTypewriter(cleanLine)
            })
            .store(in: &cancellables)
    }
    
    private func addPoemLineWithTypewriter(_ text: String) {
        guard !text.isEmpty else { return }
        
        // Stop any existing typing
        typingTimer?.invalidate()
        isTyping = true
        currentTypingText = ""
        
        let characters = Array(text)
        var index = 0
        
        // Typewriter effect: one character every 100ms (slowed down from 50ms to reduce UI thrashing)
        typingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            if index < characters.count {
                self.currentTypingText += String(characters[index])
                index += 1
            } else {
                timer.invalidate()
                self.isTyping = false
                
                // Add to poem lines
                let newLine = PoemLine(text: text, timestamp: Date())
                self.poemLines.append(newLine)
                // Clear typing line immediately to avoid duplicate display
                self.currentTypingText = ""
                print("🖋️ Typing finished, added line: \(text)")
                
                // Keep only last 5 lines
                if self.poemLines.count > 5 {
                    self.poemLines.removeFirst()
                }
                
                // Clear current typing after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if !self.isTyping {
                        self.currentTypingText = ""
                    }
                }
            }
        }
    }
    
    func clearPoem() {
        capturedWords.removeAll()
        poemLines.removeAll()
        currentTypingText = ""
        typingTimer?.invalidate()
        isTyping = false
    }
}
