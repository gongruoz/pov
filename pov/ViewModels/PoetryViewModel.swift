import Foundation
import Combine

struct PoemLine: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let timestamp: Date
    let triggerWord: String?
    
    init(text: String, timestamp: Date = Date(), triggerWord: String? = nil) {
        self.text = text
        self.timestamp = timestamp
        self.triggerWord = triggerWord
    }
}

class PoetryViewModel: ObservableObject {
    // MARK: - Published State
    
    /// Generated poem lines
    @Published var poemLines: [PoemLine] = []
    
    /// Current line being typed (typewriter effect)
    @Published var currentTypingText: String = ""
    @Published var isTyping: Bool = false
    
    /// Reference to the shared poetic context
    weak var arManager: ARManager?
    
    // MARK: - Private State
    
    private let llmService = LLMService()
    private var cancellables = Set<AnyCancellable>()
    private var typingTimer: Timer?
    
    // Debounce poem generation to avoid rapid-fire
    private var lastPoemGenerationTime: Date?
    private let poemGenerationCooldown: TimeInterval = 2.0
    
    // MARK: - Word Capture (Called by ARManager)
    
    /// Called when user captures (selects) a word
    func captureWord(_ word: String) {
        guard let arManager = arManager else {
            print("⚠️ Poetry: ARManager not connected")
            return
        }
        
        print("📝 Poetry: Captured '\(word)'")
        
        // Check cooldown
        if let lastTime = lastPoemGenerationTime,
           Date().timeIntervalSince(lastTime) < poemGenerationCooldown {
            print("⏳ Poetry: Cooldown active, skipping generation")
            return
        }
        
        // Generate poem line with full context
        generatePoemLine(triggerWord: word, context: arManager.getCurrentContext())
    }
    
    /// Called when user uncaptures a word
    func uncaptureWord(_ word: String) {
        print("📝 Poetry: Released '\(word)'")
        // We don't remove poem lines, they stay as part of the river
    }
    
    // MARK: - Poem Generation
    
    private func generatePoemLine(triggerWord: String, context: PoeticSessionContext) {
        lastPoemGenerationTime = Date()
        
        // Prepare context with current poem lines
        var fullContext = context
        fullContext.poemLines = poemLines.map { $0.text }
        
        print("🎭 Generating poem...")
        print("   Anchors: \(fullContext.activeAnchors)")
        print("   Objects: \(fullContext.formatObjectSequence())")
        print("   Visual: \(fullContext.latestVisualDescription ?? "none")")
        print("   History: \(fullContext.formatSelectionHistory())")
        
        llmService.generate(mode: .generatePoem(context: fullContext))
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("❌ Poetry generation error: \(error)")
                }
            }, receiveValue: { [weak self] line in
                guard let self = self else { return }
                
                let cleanLine = self.cleanPoemLine(line)
                print("🎭 Generated: '\(cleanLine)'")
                
                // Show with typewriter effect
                self.addPoemLineWithTypewriter(cleanLine, triggerWord: triggerWord)
                
                // Update ARManager's context
                self.arManager?.addPoemLine(cleanLine)
            })
            .store(in: &cancellables)
    }
    
    private func cleanPoemLine(_ line: String) -> String {
        return line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\u{201C}", with: "") // Left double quote
            .replacingOccurrences(of: "\u{201D}", with: "") // Right double quote
            .replacingOccurrences(of: "「", with: "")
            .replacingOccurrences(of: "」", with: "")
    }
    
    // MARK: - Typewriter Effect
    
    private func addPoemLineWithTypewriter(_ text: String, triggerWord: String?) {
        guard !text.isEmpty else { return }
        
        // Stop any existing typing
        typingTimer?.invalidate()
        isTyping = true
        currentTypingText = ""
        
        let characters = Array(text)
        var index = 0
        
        // Typewriter: one character every 80ms
        typingTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            if index < characters.count {
                self.currentTypingText += String(characters[index])
                index += 1
            } else {
                timer.invalidate()
                self.finishTyping(text: text, triggerWord: triggerWord)
            }
        }
    }
    
    private func finishTyping(text: String, triggerWord: String?) {
        isTyping = false
        
        // Add to poem lines
        let newLine = PoemLine(text: text, timestamp: Date(), triggerWord: triggerWord)
        poemLines.append(newLine)
        
        // Clear typing text
        currentTypingText = ""
        
        print("🖋️ Line added: '\(text)'")
        
        // Keep only last 6 lines visible
        if poemLines.count > 6 {
            poemLines.removeFirst()
        }
    }
    
    // MARK: - Clear
    
    func clearPoem() {
        poemLines.removeAll()
        currentTypingText = ""
        typingTimer?.invalidate()
        isTyping = false
        lastPoemGenerationTime = nil
    }
}
