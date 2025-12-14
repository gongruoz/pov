//
//  AppConfig.swift
//  pov
//
//  Created by jane on 12/13/25.
//

import Foundation

struct AppConfig {
    static let maxPoemLineHistory = 3
    static let visionFetchInterval: TimeInterval = 6.0 // Slightly faster vision
    static let maxVisualContextHistory = 5
    static let maxWordQueueSize = 15
    
    // Floating Words
    static let maxFloatingWords = 15
    static let floatingWordLifespan: TimeInterval = 12.0 // Longer life
    static let snowfallInterval: TimeInterval = 2.0
    static let floatingWordMaxY: Double = 0.65
    
    // LLM Config (Qwen)
    static let apiKey = "sk-ihovlhiteedbgmxwgsrstyozjimjymhyqmljjxagovyhsmsk"
    static let apiBaseURL = "https://api.siliconflow.cn/v1/chat/completions"
    static let modelName = "Qwen/Qwen3-VL-30B-A3B-Instruct" 
    
    // Poem Generation
    static let poemGenerationCooldown: TimeInterval = 5.0
}
