import Foundation
import UIKit

// MARK: - Object Detection (Fast Stream)

/// A single object detected by the local ML model
struct ObjectDetection: Identifiable, Codable {
    let id: UUID
    let label: String
    let confidence: Float
    let timestamp: Date
    
    init(label: String, confidence: Float, timestamp: Date = Date()) {
        self.id = UUID()
        self.label = label
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

// MARK: - Visual Context (Slow Stream)

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

/// Tracks when user selects/deselects a word - captures intent over time
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
    /// Time-ordered sequence of detected objects (Fast Stream)
    var objectSequence: [ObjectDetection] = []
    
    /// Time-ordered visual descriptions (Slow Stream)
    var visualContexts: [VisualContext] = []
    
    /// User's selection history - reveals intent patterns
    var selectionHistory: [SelectionEvent] = []
    
    /// Currently selected words (active anchors)
    var activeAnchors: [String] = []
    
    /// Previously generated poem lines
    var poemLines: [String] = []
    
    // MARK: - Computed Properties
    
    /// Recent objects for prompt context (last 10)
    var recentObjects: [String] {
        objectSequence.suffix(10).map { $0.label }
    }
    
    /// Latest visual description
    var latestVisualDescription: String? {
        visualContexts.last?.description
    }
    
    /// Words selected by user (shows intent pattern)
    var selectedWords: [String] {
        selectionHistory.filter { $0.action == .selected }.map { $0.word }
    }
    
    /// Recent poem lines for continuity (last 3)
    var recentPoemLines: [String] {
        Array(poemLines.suffix(3))
    }
    
    // MARK: - Formatting for Prompts
    
    /// Format object sequence as comma-separated string
    func formatObjectSequence() -> String {
        recentObjects.joined(separator: ", ")
    }
    
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
        recentPoemLines.joined(separator: "\n")
    }
}

// MARK: - Floating Word with Source Context

/// Enhanced floating word with generation context
struct FloatingWord: Identifiable {
    let id: UUID
    let text: String
    var position: CGPoint // Normalized coordinates (0-1)
    var opacity: Double = 0.0 // Start invisible for fade in
    var scale: Double = 0.5   // Start small
    var createdAt: Date = Date()
    
    /// The source that triggered this word (object label or visual description)
    let sourceContext: String?
    
    init(text: String, position: CGPoint, sourceContext: String? = nil) {
        self.id = UUID()
        self.text = text
        self.position = position
        self.sourceContext = sourceContext
    }
}
