import Foundation
import CoreGraphics
import UIKit

struct AppConfig {
    // ============================================================
    // API Configuration - Qwen
    // ============================================================
    static let apiKey = "sk-ihovlhiteedbgmxwgsrstyozjimjymhyqmljjxagovyhsmsk"
    static let modelName = "Qwen/Qwen3-VL-8B-Instruct"
    static let apiBaseURL = "https://api.siliconflow.cn/v1/chat/completions"
    
    // ============================================================
    // Text Configuration
    // ============================================================
    static let textExtrusionDepth: Float = 0.003 // 3mm
    static let textFontSize: CGFloat = 0.025 // 2.5cm
    static let fontWeight: UIFont.Weight = .medium
    
    // ============================================================
    // Visual Style (Bauhaus)
    // ============================================================
    static let primaryColor: UIColor = .white
    static let colorPalette: [UIColor] = [
        .white,
        UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0), // Red
        UIColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0), // Blue
        UIColor(red: 1.0, green: 0.85, blue: 0.1, alpha: 1.0) // Yellow
    ]
    
    // ============================================================
    // Timing & Thresholds
    // ============================================================
    
    /// How often the fast stream (CoreML) processes frames
    static let fastStreamInterval: TimeInterval = 5
    
    /// How often the slow stream (Vision API) captures descriptions
    static let slowStreamInterval: TimeInterval = 6.0
    
    /// How long floating words stay on screen before fading
    static let floatingWordLifespan: TimeInterval = 8.0
    
    /// Cooldown before the same word can appear again
    static let wordCooldownDuration: TimeInterval = 5.0
    
    /// Minimum time between poem generation attempts
    static let poemGenerationCooldown: TimeInterval = 2.0
    
    /// Locomotion velocity threshold for gaze detection
    static let locomotionVelocityThreshold: Double = 0.15 // rad/s
    
    /// Gaze duration threshold
    static let gazeDurationThreshold: TimeInterval = 1.0
    
    // ============================================================
    // Context Limits
    // ============================================================
    
    /// Maximum object detections to keep in history
    static let maxObjectHistory: Int = 50
    
    /// Maximum visual descriptions to keep
    static let maxVisualContextHistory: Int = 20
    
    /// Maximum poem lines to keep for continuity
    static let maxPoemLineHistory: Int = 10
    
    /// Maximum floating words on screen at once
    static let maxFloatingWords: Int = 5
    
    // ============================================================
    // Debug
    // ============================================================
    static let debugMode = true
}
