import Foundation
import CoreMotion
import Combine

// Local defaults to avoid AppConfig visibility issues
private enum MotionDefaults {
    static let locomotionVelocityThreshold: Double = 0.15
    static let gazeDurationThreshold: TimeInterval = 1.0
}

enum VisionState {
    case locomotion // Moving fast
    case gaze // Staring still
}

/// Handles motion detection to determine if user is moving or gazing
/// Frame processing has been moved to ARManager for better memory management
class VisionEngine: ObservableObject {
    @Published var state: VisionState = .locomotion
    
    // Motion
    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue() // Background queue for motion processing
    private var lastGazeTime: Date = Date()
    private var isGazing = false
    
    init() {
        motionQueue.name = "com.pov.motionQueue"
        motionQueue.qualityOfService = .userInteractive
        startMotionUpdates()
    }
    
    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.1
        // Use background queue instead of .main to avoid freezing UI
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            self.processMotion(motion)
        }
    }
    
    private func processMotion(_ motion: CMDeviceMotion) {
        let rotationRate = motion.rotationRate
        let magnitude = sqrt(pow(rotationRate.x, 2) + pow(rotationRate.y, 2) + pow(rotationRate.z, 2))
        
        // State updates must happen on Main Thread
        DispatchQueue.main.async {
            if magnitude < MotionDefaults.locomotionVelocityThreshold {
                // Low movement
                if !self.isGazing {
                    if Date().timeIntervalSince(self.lastGazeTime) > MotionDefaults.gazeDurationThreshold {
                        self.isGazing = true
                        self.state = .gaze
                    }
                }
            } else {
                // High movement
                self.isGazing = false
                self.lastGazeTime = Date()
                self.state = .locomotion
            }
        }
    }
    
    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}
