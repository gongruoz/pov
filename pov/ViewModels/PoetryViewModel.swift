import Foundation
import Combine

struct PoemLine: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let timestamp: Date
    let triggerWord: String?
}

class PoetryViewModel: ObservableObject {
    @Published var poemLines: [PoemLine] = []
    @Published var currentTypingText: String = ""
    @Published var isTyping: Bool = false
    @Published var justCompletedText: String = "" // Line that just finished typing, stays until next starts
    weak var arManager: ARManager?
    
    private let llmService = LLMService()
    private var cancellables = Set<AnyCancellable>()
    private var typingTimer: Timer?
    
    // Buffering & Debouncing
    private var selectedWordBuffer: [String] = []
    private var debounceTimer: Timer?
    private var isGenerating = false
    
    // Config
    private let debounceInterval: TimeInterval = 3.0
    
    func captureWord(_ word: String) {
        selectedWordBuffer.append(word)
        resetDebounceTimer()
    }
    
    func uncaptureWord(_ word: String) {
        // Optional: remove from buffer if deselected within window?
        // keeping simple: just append selections
    }
    
    private func resetDebounceTimer() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            self?.tryTriggerGeneration()
        }
    }
    
    private func tryTriggerGeneration() {
        // Don't interrupt typing. If typing, wait until done (handled by completion of typing)
        guard let manager = arManager, !selectedWordBuffer.isEmpty else { return }
        
        if isTyping || isGenerating {
            // Re-schedule check
            print("⏳ Still typing/generating, queueing request...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.tryTriggerGeneration()
            }
            return
        }
        
        generate(manager: manager)
    }
    
    private func generate(manager: ARManager) {
        isGenerating = true
        let triggers = selectedWordBuffer
        selectedWordBuffer.removeAll()
        
        print("🧠 Generating poem for: \(triggers)")
        
        var context = manager.getCurrentContext()
        context.activeAnchors = triggers
        context.poemLines = poemLines.map { $0.text }
        
        llmService.generate(mode: .generatePoem(context: context))
            .compactMap { $0 as? String }
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] _ in
                self?.isGenerating = false
            }, receiveValue: { [weak self] line in
                self?.typewrite(line, trigger: triggers.last)
                self?.arManager?.addPoemLine(line)
            })
            .store(in: &cancellables)
    }
    
    private func typewrite(_ text: String, trigger: String?) {
        let clean = text.replacingOccurrences(of: "/", with: ",")
        typingTimer?.invalidate()
        
        // Move any justCompleted line to history before starting new one
        if !justCompletedText.isEmpty {
            // This will be handled in the view with animation
        }
        
        isTyping = true
        currentTypingText = ""
        justCompletedText = "" // Clear any previous just-completed line
        
        let chars = Array(clean)
        var idx = 0
        
        typingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self = self else { return }
            if idx < chars.count {
                self.currentTypingText.append(chars[idx])
                idx += 1
            } else {
                t.invalidate()
                self.isTyping = false
                
                // Keep as "just completed" - don't add to history yet
                self.justCompletedText = clean
                self.currentTypingText = ""
                
                // Add to poemLines (for LLM context) but view will show it as justCompleted
                self.poemLines.append(PoemLine(text: clean, timestamp: Date(), triggerWord: trigger))
                if self.poemLines.count > AppConfig.maxPoemLineHistory { self.poemLines.removeFirst() }
                
                // Clear selected words after poem line is complete
                self.arManager?.clearSelectedWords()
                self.arManager?.addPoemLine(clean)
                
                // Check if more words were buffered while typing
                // Add delay so user can see the just-completed line before next starts
                if !self.selectedWordBuffer.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.tryTriggerGeneration()
                    }
                }
            }
        }
    }
}
