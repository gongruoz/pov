import Foundation
import RealityKit
import UIKit

enum WordState {
    case floating
    case anchored
}

struct PoeticWord: Identifiable {
    let id = UUID()
    let text: String
    var state: WordState = .floating
    var position: SIMD3<Float>
    // orientation logic will be handled by the Entity transform, but we might want to store normal if needed
    
    // For Phase 1, we just need basic properties
}

