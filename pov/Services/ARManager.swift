import AVFoundation
import SwiftUI
import Combine
import Vision

struct FloatingWord: Identifiable {
    let id = UUID()
    let text: String
    var position: CGPoint // Normalized coordinates (0-1)
    var opacity: Double = 0.0 // Start invisible for fade in
    var scale: Double = 0.5   // Start small
    var createdAt: Date = Date()
}

class ARManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    // Camera Session
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    
    // Preview Layer (to be added to view)
    // We don't store the view here anymore, just the session/layer logic
    
    // Frame processing state
    private var isProcessing = false            // object->word pipeline
    private var lastProcessedTime: TimeInterval = 0
    private var isProcessingVision = false      // image->text pipeline
    private var lastVisionTime: TimeInterval = 0
    
    // ============================================================
    // Word Management
    // ============================================================
    
    // All detected words (history log)
    @Published var detectedWordsLog: [String] = []
    
    // Active floating words on screen (2D)
    @Published var floatingWords: [FloatingWord] = []
    
    // Words selected/kept by user
    @Published var keptWords: [FloatingWord] = []
    
    // Word History for Cooldown
    private var wordCooldowns: [String: Date] = [:]
    private let cooldownDuration: TimeInterval = 3.0
    
    // Maximum floating words on screen
    private let maxFloatingWords = 5
    
    // Dependencies
    private let llmService = LLMService()
    private let coreMLService = CoreMLService()
    private var cancellables = Set<AnyCancellable>()
    weak var recorderService: RecorderService?
    
    // Haptics
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    
    // Callbacks for Poetry integration
    var onWordSelected: ((String) -> Void)?
    var onWordUnselected: ((String) -> Void)?
    
    override init() {
        super.init()
        setupCamera()
        startTimer()
        
        // Test Gemini API connection on startup
        testGeminiConnection()
    }
    
    private func setupCamera() {
        captureSession.sessionPreset = .high
        
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("❌ Camera not available")
            return
        }
        // Audio input
        let audioDevice = AVCaptureDevice.default(for: .audio)
        let audioInput = audioDevice.flatMap { try? AVCaptureDeviceInput(device: $0) }
        
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        if let audioInput, captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            // Use a dedicated serial queue for frame processing to avoid blocking main thread
            let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInteractive)
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            if let connection = videoOutput.connection(with: .video),
               connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }
        
        if captureSession.canAddOutput(audioOutput) {
            captureSession.addOutput(audioOutput)
            if let recorderService {
                audioOutput.setSampleBufferDelegate(recorderService, queue: DispatchQueue(label: "audioQueue"))
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
            print("🎥 Camera Session started")
        }
    }
    
    func attachRecorder(_ recorder: RecorderService) {
        self.recorderService = recorder
        recorder.arManager = self
        // Attach audio delegate if session already configured
        audioOutput.setSampleBufferDelegate(recorder, queue: DispatchQueue(label: "audioQueue"))
    }
    
    private func startTimer() {
        // Timer to update word animations/lifespan
        Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.updateWords()
        }
    }
    
    private func updateWords() {
        // Animation logic
        let now = Date()
        var newFloatingWords: [FloatingWord] = []
        
        for var word in floatingWords {
            let age = now.timeIntervalSince(word.createdAt)
            
            // Fade in
            if age < 0.5 {
                word.opacity = age / 0.5
                word.scale = 0.5 + (age / 0.5) * 0.5 // 0.5 -> 1.0
            } else if age > AppConfig.floatingWordLifespan - 0.5 {
                // Fade out
                let remaining = AppConfig.floatingWordLifespan - age
                word.opacity = max(0, remaining / 0.5)
            } else {
                word.opacity = 1.0
                word.scale = 1.0
            }
            
            // Drift slightly
            word.position.y -= 0.0005 // Float up
            
            if age < AppConfig.floatingWordLifespan {
                newFloatingWords.append(word)
            }
        }
        
        self.floatingWords = newFloatingWords
    }
    
    // MARK: - Camera Delegate
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Forward video frames to recorder (only from videoOutput)
        if output === videoOutput {
            recorderService?.processVideoFrame(sampleBuffer)
        }
        
        let now = Date().timeIntervalSince1970
        
        // ----------------------------
        // CoreML Object Detection: every 2 seconds
        // ----------------------------
        if !isProcessing, now - lastProcessedTime > 2.0 {
            isProcessing = true
            lastProcessedTime = now
            
            // Process on background
            performDetection(pixelBuffer: pixelBuffer)
        }
        
        // ----------------------------
        // Vision (imageToText): every 6 seconds
        // ----------------------------
        if !isProcessingVision, now - lastVisionTime > 6.0 {
            isProcessingVision = true
            lastVisionTime = now
            
            // Process on background
            performVisionAdjectives(pixelBuffer: pixelBuffer)
        }
    }
    
    // MARK: - Logic (Same as before)
    
    private func testGeminiConnection() {
        // ... same logic
        llmService.generatePoeticWord(mode: .textToText(tag: "test", color: "neutral"))
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { word in
                print("✅ Gemini API connected! Test response: '\(word)'")
            })
            .store(in: &cancellables)
    }
    
    private func performDetection(pixelBuffer: CVPixelBuffer) {
        coreMLService.classify(image: pixelBuffer)
            .receive(on: DispatchQueue.main)
            .flatMap { [weak self] tag -> AnyPublisher<String, Error> in
                guard let self = self else { return Fail(error: URLError(.unknown)).eraseToAnyPublisher() }
                return self.llmService.generatePoeticWord(mode: .textToText(tag: tag, color: "neutral"))
            }
            .sink(receiveCompletion: { [weak self] _ in
                self?.isProcessing = false
            }, receiveValue: { [weak self] poeticWord in
                self?.handleDetectedWord(poeticWord)
            })
            .store(in: &cancellables)
    }
    
    private func performVisionAdjectives(pixelBuffer: CVPixelBuffer) {
        // Create a copy or use CIImage directly to avoid buffer locking issues?
        // Actually, creating CIImage is lightweight.
        // We need to convert to UIImage for the API.
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext() // Create local context
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            isProcessingVision = false
            return
        }
        let uiImage = UIImage(cgImage: cgImage)
        
        llmService.generatePoeticWord(mode: .imageToText(image: uiImage))
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] _ in
                self?.isProcessingVision = false
            }, receiveValue: { [weak self] words in
                let parts = words.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                for word in parts {
                    self?.handleDetectedWord(word)
                }
            })
            .store(in: &cancellables)
    }
    
    private func handleDetectedWord(_ word: String) {
        let cleanWord = word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
            .lowercased()
        
        guard !cleanWord.isEmpty else { return }
        
        detectedWordsLog.append(cleanWord)
        
        let now = Date()
        wordCooldowns = wordCooldowns.filter { $0.value > now }
        
        if wordCooldowns[cleanWord] != nil { return }
        
        // Check duplication in floating words
        if floatingWords.contains(where: { $0.text == cleanWord }) || keptWords.contains(where: { $0.text == cleanWord }) {
            return
        }
        
        if floatingWords.count >= maxFloatingWords { return }
        
        wordCooldowns[cleanWord] = now.addingTimeInterval(cooldownDuration)
        
        spawnWord(cleanWord)
    }
    
    private func spawnWord(_ text: String) {
        // Random position on screen (avoid edges)
        // x: 0.1 - 0.9
        // y: 0.2 - 0.6 (Keep upper/middle part, avoid bottom controls)
        let x = Double.random(in: 0.2...0.8)
        let y = Double.random(in: 0.3...0.6)
        
        let word = FloatingWord(text: text, position: CGPoint(x: x, y: y))
        floatingWords.append(word)
        print("🎯 Spawned: '\(text)' at \(x), \(y)")
    }
    
    // MARK: - Interactions
    
    func toggleWordSelection(_ wordId: UUID) {
        if let index = floatingWords.firstIndex(where: { $0.id == wordId }) {
            // Select: Move from floating to kept
            let word = floatingWords[index]
            floatingWords.remove(at: index)
            keptWords.append(word)
            
            impactMedium.impactOccurred()
            onWordSelected?(word.text)
        } else if let index = keptWords.firstIndex(where: { $0.id == wordId }) {
            // Unselect: Remove or move back?
            // "Tap to select and keep them"
            // Usually tapping again might release it. Let's release it back to floating or just remove it.
            // Let's release it back to floating for fun, or just delete it.
            // Let's move back to floating to give it a chance to fade out.
            var word = keptWords[index]
            word.createdAt = Date() // Reset timer so it fades out eventually
            keptWords.remove(at: index)
            floatingWords.append(word)
            
            impactLight.impactOccurred()
            onWordUnselected?(word.text)
        }
    }
}
