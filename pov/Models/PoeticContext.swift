import Foundation
import CoreGraphics

// MARK: - Visual Context (Vision Stream)

/// A visual description captured from the scene
struct VisualContext: Identifiable, Codable {
    let id: UUID
    let description: String
    let timestamp: Date
    
    init(description: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.description = description
        self.timestamp = timestamp
    }
}

// MARK: - User Selection Event

/// Tracks when user selects/deselects a word
struct SelectionEvent: Identifiable, Codable {
    let id: UUID
    let word: String
    let action: SelectionAction
    let timestamp: Date
    
    enum SelectionAction: String, Codable {
        case selected
        case deselected
    }
    
    init(word: String, action: SelectionAction, timestamp: Date = Date()) {
        self.id = UUID()
        self.word = word
        self.action = action
        self.timestamp = timestamp
    }
}

// MARK: - Poetic Session Context

/// Aggregates all context for poetry generation
struct PoeticSessionContext {
    // REMOVED: objectSequence (CoreML legacy)
    
    /// Time-ordered visual descriptions (Slow Stream)
    var visualContexts: [VisualContext] = []
    
    /// User's selection history
    var selectionHistory: [SelectionEvent] = []
    
    /// Currently selected words (active anchors)
    var activeAnchors: [String] = []
    
    /// Previously generated poem lines
    var poemLines: [String] = []
    
    // MARK: - Computed Properties
    
    /// Latest visual description
    var latestVisualDescription: String? {
        visualContexts.last?.description
    }
    
    /// Recent poem lines for continuity (last 3)
    var recentPoemLines: [String] {
        Array(poemLines.suffix(3))
    }
    
    // MARK: - Formatting for Prompts
    
    /// Format selection history showing user's choices
    func formatSelectionHistory() -> String {
        let recentSelections = selectionHistory
            .filter { $0.action == .selected }
            .suffix(8)
            .map { $0.word }
        return recentSelections.joined(separator: " → ")
    }
    
    /// Format poem history for continuity
    func formatPoemHistory() -> String {
        return recentPoemLines.joined(separator: "\n")
    }
}

// MARK: - Floating Word

struct FloatingWord: Identifiable {
    let id: UUID
    let text: String
    var position: CGPoint // Normalized coordinates (0-1)
    var opacity: Double = 0.0
    var scale: Double = 0.5
    var createdAt: Date = Date()
    var isSelected: Bool = false // Selected/fixed state
    var isFadingOut: Bool = false // Marked for slow fade removal
    var fadeOutStartTime: Date? = nil // When fade out started
    
    /// The source that triggered this word (usually "vision")
    let sourceContext: String?
    
    init(text: String, position: CGPoint, sourceContext: String? = nil) {
        self.id = UUID()
        self.text = text
        self.position = position
        self.sourceContext = sourceContext
    }
}

