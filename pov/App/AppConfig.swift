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
    static let locomotionVelocityThreshold: Double = 0.15 // rad/s
    static let gazeDurationThreshold: TimeInterval = 1.0 // seconds
    static let floatingWordLifespan: TimeInterval = 2.0 // seconds (ease in, stay 2s, ease out)
    
    // ============================================================
    // Debug
    // ============================================================
    static let debugMode = true
}
