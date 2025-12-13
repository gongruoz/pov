import AVFoundation
import SwiftUI
import Combine
import Vision

class ARManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    // MARK: - Camera Session
    
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    
    // MARK: - Frame Processing State
    
    private var isProcessingFastStream = false      // CoreML object detection
    private var lastFastStreamTime: TimeInterval = 0
    private var isProcessingSlowStream = false      // Vision API description
    private var lastSlowStreamTime: TimeInterval = 0
    
    // MARK: - Poetic Context (The Heart of the System)
    
    /// Shared context that accumulates all sensory data
    @Published var poeticContext = PoeticSessionContext()
    
    // MARK: - Word Management
    
    /// Active floating words on screen (candidates for selection)
    @Published var floatingWords: [FloatingWord] = []
    
    /// Words selected/kept by user (anchors)
    @Published var keptWords: [FloatingWord] = []
    
    /// Word cooldown to prevent repetition
    private var wordCooldowns: [String: Date] = [:]
    private let cooldownDuration: TimeInterval = 5.0
    
    /// Maximum floating words on screen
    private let maxFloatingWords = 8
    
    // MARK: - Dependencies
    
    private let llmService = LLMService()
    private let coreMLService = CoreMLService()
    private var cancellables = Set<AnyCancellable>()
    weak var recorderService: RecorderService?
    
    // MARK: - Haptics
    
    private let impactLight = UIImpactFeedbackGenerator(style: .rigid)
    
    // MARK: - Callbacks
    
    var onWordSelected: ((String) -> Void)?
    var onWordUnselected: ((String) -> Void)?
    var onContextUpdated: ((PoeticSessionContext) -> Void)?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        impactLight.prepare()
        setupCamera()
        startAnimationTimer()
        testConnection()
    }
    
    func triggerHaptic() {
        DispatchQueue.main.async { [weak self] in
            self?.impactLight.impactOccurred(intensity: 1.0)
            self?.impactLight.prepare()
        }
    }
    
    // MARK: - Camera Setup
    
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
        audioOutput.setSampleBufferDelegate(recorder, queue: DispatchQueue(label: "audioQueue"))
    }
    
    // MARK: - Animation Timer
    
    private func startAnimationTimer() {
        Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.updateFloatingWords()
        }
    }
    
    private func updateFloatingWords() {
        let now = Date()
        var newFloatingWords: [FloatingWord] = []
        
        for var word in floatingWords {
            let age = now.timeIntervalSince(word.createdAt)
            
            // Fade in (0 - 0.5s)
            if age < 0.5 {
                word.opacity = age / 0.5
                word.scale = 0.5 + (age / 0.5) * 0.5
            }
            // Fade out (last 0.5s of lifespan)
            else if age > AppConfig.floatingWordLifespan - 0.5 {
                let remaining = AppConfig.floatingWordLifespan - age
                word.opacity = max(0, remaining / 0.5)
            }
            // Fully visible
            else {
                word.opacity = 1.0
                word.scale = 1.0
            }
            
            
            if age < AppConfig.floatingWordLifespan {
                newFloatingWords.append(word)
            }
        }
        
        self.floatingWords = newFloatingWords
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Forward video frames to recorder
        if output === videoOutput {
            recorderService?.processVideoFrame(sampleBuffer)
        }
        
        let now = Date().timeIntervalSince1970
        
        // ----------------------------
        // FAST STREAM: CoreML Object Detection (every 2 seconds)
        // ----------------------------
        if !isProcessingFastStream, now - lastFastStreamTime > AppConfig.fastStreamInterval {
            isProcessingFastStream = true
            lastFastStreamTime = now
            processFastStream(pixelBuffer: pixelBuffer)
        }
        
        // ----------------------------
        // SLOW STREAM: Vision API Description (every 6 seconds)
        // ----------------------------
        if !isProcessingSlowStream, now - lastSlowStreamTime > 6.0 {
            isProcessingSlowStream = true
            lastSlowStreamTime = now
            processSlowStream(pixelBuffer: pixelBuffer)
        }
    }
    
    // MARK: - Fast Stream: Object Detection → Pebbles
    
    private func processFastStream(pixelBuffer: CVPixelBuffer) {
        coreMLService.classify(image: pixelBuffer)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] _ in
                self?.isProcessingFastStream = false
            }, receiveValue: { [weak self] detectedLabel in
                guard let self = self else { return }
                
                // Record the object detection in context
                let detection = ObjectDetection(
                    label: detectedLabel,
                    confidence: 1.0, // CoreML doesn't easily expose confidence here
                    timestamp: Date()
                )
                self.poeticContext.objectSequence.append(detection)
                
                // Limit history size
                if self.poeticContext.objectSequence.count > 50 {
                    self.poeticContext.objectSequence.removeFirst()
                }
                
                print("🔍 Fast Stream: '\(detectedLabel)' | Sequence: \(self.poeticContext.recentObjects)")
                
                // Generate 5 pebbles based on current context
                self.generatePebbles(forObject: detectedLabel)
            })
            .store(in: &cancellables)
    }
    
    // MARK: - Slow Stream: Visual Description
    
    private func processSlowStream(pixelBuffer: CVPixelBuffer) {
        // Convert pixel buffer to UIImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            isProcessingSlowStream = false
            return
        }
        let uiImage = UIImage(cgImage: cgImage)
        
        // Get plain description of the scene
        llmService.generate(mode: .imageToDescription(image: uiImage))
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] _ in
                self?.isProcessingSlowStream = false
            }, receiveValue: { [weak self] description in
                guard let self = self else { return }
                
                // Record the visual context
                let visualContext = VisualContext(description: description)
                self.poeticContext.visualContexts.append(visualContext)
                
                // Limit history size
                if self.poeticContext.visualContexts.count > 20 {
                    self.poeticContext.visualContexts.removeFirst()
                }
                
                print("👁️ Slow Stream: '\(description)'")
                
                // Notify listeners
                self.onContextUpdated?(self.poeticContext)
            })
            .store(in: &cancellables)
    }
    
    // MARK: - Generate Pebbles (5 Word Options)
    
    private func generatePebbles(forObject currentObject: String) {
        llmService.generate(mode: .generatePebbles(context: poeticContext, currentObject: currentObject))
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("❌ Pebble generation error: \(error)")
                }
            }, receiveValue: { [weak self] pebblesText in
                guard let self = self else { return }
                
                // Parse the 5 pebbles (one per line)
                let pebbles = pebblesText
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .prefix(5)
                
                print("🪨 Pebbles received: \(pebbles)")
                
                for pebble in pebbles {
                    self.spawnWordIfAllowed(pebble, sourceContext: currentObject)
                }
            })
            .store(in: &cancellables)
    }
    
    // MARK: - Word Spawning
    
    private func spawnWordIfAllowed(_ text: String, sourceContext: String?) {
        let cleanWord = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanWord.isEmpty else { return }
        
        // Clean up expired cooldowns
        let now = Date()
        wordCooldowns = wordCooldowns.filter { $0.value > now }
        
        // Check cooldown
        if wordCooldowns[cleanWord] != nil { return }
        
        // Check duplication
        if floatingWords.contains(where: { $0.text == cleanWord }) ||
           keptWords.contains(where: { $0.text == cleanWord }) {
            return
        }
        
        // Check capacity
        if floatingWords.count >= maxFloatingWords { return }
        
        // Set cooldown
        wordCooldowns[cleanWord] = now.addingTimeInterval(cooldownDuration)
        
        // Spawn with distributed positioning
        let word = createFloatingWord(text: cleanWord, sourceContext: sourceContext)
        floatingWords.append(word)
        
        print("🎯 Spawned: '\(cleanWord)' from '\(sourceContext ?? "unknown")'")
    }
    
        
    // 新增：碰撞检测位置生成器
    private func getSafeRandomPosition() -> CGPoint {
        let maxRetries = 20
        // 设定最小间距 (屏幕宽度的 20% ~ 25%，根据你的字号大小调整)
        // 调大这个数值可以让文字分得更开
        let minDistance: CGFloat = 0.22
        
        for _ in 0..<maxRetries {
            // 1. 生成随机坐标
            // x: 0.1 ~ 0.9 (避开左右边缘)
            // y: 0.15 ~ 0.75 (避开顶部和底部遮挡区，范围比之前更广，显得更松散)
            let candidate = CGPoint(
                x: CGFloat.random(in: 0.1...0.9),
                y: CGFloat.random(in: 0.15...0.75)
            )
            
            // 2. 检查与现有词的距离
            var isSafe = true
            for word in floatingWords {
                let dx = candidate.x - word.position.x
                let dy = candidate.y - word.position.y
                let distance = sqrt(dx*dx + dy*dy)
                
                if distance < minDistance {
                    isSafe = false
                    break
                }
            }
            
            // 3. 同时也检查与 "Kept Words" (已选中词) 的距离，防止重叠
            if isSafe {
                for word in keptWords {
                    let dx = candidate.x - word.position.x
                    let dy = candidate.y - word.position.y
                    let distance = sqrt(dx*dx + dy*dy)
                    
                    if distance < minDistance {
                        isSafe = false
                        break
                    }
                }
            }
            
            if isSafe {
                return candidate
            }
        }
        
        // 如果尝试多次都找不到位置（太挤了），就在允许范围内随机放一个
        return CGPoint(
            x: CGFloat.random(in: 0.1...0.9),
            y: CGFloat.random(in: 0.2...0.7)
        )
    }

    // 修改后的 createFloatingWord
    private func createFloatingWord(text: String, sourceContext: String?) -> FloatingWord {
        // 使用上面的安全位置生成器
        let position = getSafeRandomPosition()
        
        return FloatingWord(
            text: text,
            position: position,
            sourceContext: sourceContext
        )
    }
    
    // MARK: - User Interactions
    
    func toggleWordSelection(_ wordId: UUID) {
        if let index = floatingWords.firstIndex(where: { $0.id == wordId }) {
            // SELECT: Move from floating to kept
            let word = floatingWords[index]
            floatingWords.remove(at: index)
            keptWords.append(word)
            
            // Record selection event in context
            let event = SelectionEvent(word: word.text, action: .selected)
            poeticContext.selectionHistory.append(event)
            poeticContext.activeAnchors.append(word.text)
            
            print("✅ Selected: '\(word.text)' | History: \(poeticContext.formatSelectionHistory())")
            
            onWordSelected?(word.text)
            
        } else if let index = keptWords.firstIndex(where: { $0.id == wordId }) {
            // DESELECT: Move back to floating
            var word = keptWords[index]
            word.createdAt = Date().addingTimeInterval(-1.0) // Reset timer
            keptWords.remove(at: index)
            floatingWords.append(word)
            
            // Record deselection event
            let event = SelectionEvent(word: word.text, action: .deselected)
            poeticContext.selectionHistory.append(event)
            poeticContext.activeAnchors.removeAll { $0 == word.text }
            
            print("❌ Deselected: '\(word.text)'")
            
            onWordUnselected?(word.text)
        }
    }
    
    // MARK: - Context Access
    
    func getCurrentContext() -> PoeticSessionContext {
        return poeticContext
    }
    
    func addPoemLine(_ line: String) {
        poeticContext.poemLines.append(line)
        // Keep only last 10 lines
        if poeticContext.poemLines.count > 10 {
            poeticContext.poemLines.removeFirst()
        }
    }
    
    // MARK: - Testing
    
    private func testConnection() {
        llmService.generate(mode: .textPrompt(prompt: "Say 'connected' in one word"))
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { word in
                print("✅ LLM API connected! Response: '\(word)'")
            })
            .store(in: &cancellables)
    }
}
