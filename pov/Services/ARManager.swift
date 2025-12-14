import AVFoundation
import SwiftUI
import Combine
import AudioToolbox

class ARManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var isFetchingVision = false
    private var lastVisionFetchTime: TimeInterval = 0
    
    @Published var poeticContext = PoeticSessionContext()
    @Published var floatingWords: [FloatingWord] = []
    @Published var keptWords: [FloatingWord] = [] // Deprecated but kept for UI binding compatibility
    
    private var wordQueue: [String] = []
    private var activeWordTexts: Set<String> = []
    private var snowfallWorkItem: DispatchWorkItem?
    
    private let llmService = LLMService()
    private var cancellables = Set<AnyCancellable>()
    weak var recorderService: RecorderService?
    
    private var impactHeavy: UIImpactFeedbackGenerator?
    private var notificationFeedback: UINotificationFeedbackGenerator?
    
    var onWordSelected: ((String) -> Void)?
    var onContextUpdated: ((PoeticSessionContext) -> Void)?
    var onFirstWordsAppeared: (() -> Void)? // Called once when first words appear
    private var hasShownFirstWords = false
    
    override init() {
        super.init()
        setupCamera()
        startAnimationTimer()
        startSnowfallSystem()
        
        // Create haptic generators on main thread
        DispatchQueue.main.async { [weak self] in
            self?.impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
            self?.notificationFeedback = UINotificationFeedbackGenerator()
            self?.impactHeavy?.prepare()
            self?.notificationFeedback?.prepare()
            print("🔔 Haptic: Generators created on main thread")
        }
    }
    
    // MARK: - Required by PoetryViewModel
    func getCurrentContext() -> PoeticSessionContext {
        return poeticContext
    }
    
    func addPoemLine(_ line: String) {
        poeticContext.poemLines.append(line)
        if poeticContext.poemLines.count > AppConfig.maxPoemLineHistory {
            poeticContext.poemLines.removeFirst()
        }
    }
    
    func triggerHaptic() {
        print("🔔 Haptic: triggerHaptic() called")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Try UIKit haptics
            self.notificationFeedback?.prepare()
            self.notificationFeedback?.notificationOccurred(.success)
            self.impactHeavy?.prepare()
            self.impactHeavy?.impactOccurred(intensity: 1.0)
            
            // Fallback: Use AudioServices vibration (works on all devices)
            AudioServicesPlaySystemSound(1519) // Peek vibration
            
            print("🔔 Haptic: All feedback methods executed")
        }
    }
    
    // MARK: - Interaction
    /// Returns true if word is now selected, false if deselected
    @discardableResult
    func toggleWordSelection(_ wordId: UUID) -> Bool {
        print("👆 Tap: toggleWordSelection called for \(wordId)")
        if let index = floatingWords.firstIndex(where: { $0.id == wordId }) {
            floatingWords[index].isSelected.toggle()
            let word = floatingWords[index]
            
            print("👆 Tap: Word '\(word.text)' is now \(word.isSelected ? "SELECTED" : "DESELECTED")")
            triggerHaptic()
            
            if word.isSelected {
                poeticContext.selectionHistory.append(SelectionEvent(word: word.text, action: .selected))
                poeticContext.activeAnchors.append(word.text)
                onWordSelected?(word.text)
                return true
            }
            return false
        } else {
            print("👆 Tap: Word not found!")
            return false
        }
    }
    
    // Called when a poem line is completed - marks selected words for slow fade out
    func clearSelectedWords() {
        let now = Date()
        for i in floatingWords.indices {
            if floatingWords[i].isSelected {
                floatingWords[i].isSelected = false
                floatingWords[i].isFadingOut = true
                floatingWords[i].fadeOutStartTime = now
            }
        }
    }
    
    // MARK: - Vision & Queue
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date().timeIntervalSince1970
        if !isFetchingVision, now - lastVisionFetchTime > AppConfig.visionFetchInterval {
            isFetchingVision = true
            lastVisionFetchTime = now
            
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            if let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) {
                let uiImage = UIImage(cgImage: cgImage)
                fetchVision(image: uiImage)
            }
        }
    }
    
    private func fetchVision(image: UIImage) {
        // Debounce Vision: If we already have enough floating words, skip vision
        if floatingWords.count >= AppConfig.maxFloatingWords {
            isFetchingVision = false
            return
        }

        let timeout: TimeInterval = 30.0
        
        llmService.generateVisionEssence(image: image)
            .timeout(.seconds(timeout), scheduler: DispatchQueue.main, customError: { URLError(.timedOut) })
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                self?.isFetchingVision = false
            },
                  receiveValue: { [weak self] response in
                guard let self = self else { return }
                self.poeticContext.visualContexts.append(VisualContext(description: response.reflection))
                if self.poeticContext.visualContexts.count > AppConfig.maxVisualContextHistory {
                    self.poeticContext.visualContexts.removeFirst()
                }
                self.enqueueWords(response.pebbles)
                self.onContextUpdated?(self.poeticContext)
            })
            .store(in: &cancellables)
    }
    
    private func enqueueWords(_ words: [String]) {
        for word in words {
            let clean = word.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty && !wordQueue.contains(clean) && !activeWordTexts.contains(clean) {
                wordQueue.append(clean)
            }
        }
        if wordQueue.count > AppConfig.maxWordQueueSize {
            wordQueue.removeFirst(wordQueue.count - AppConfig.maxWordQueueSize)
        }
    }
    
    private func startSnowfallSystem() {
        snowfallWorkItem?.cancel()
        let interval = AppConfig.snowfallInterval * Double.random(in: 0.8...1.2)
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.floatingWords.count < AppConfig.maxFloatingWords, !self.wordQueue.isEmpty {
                self.spawnWord(self.wordQueue.removeFirst())
            }
            self.startSnowfallSystem()
        }
        snowfallWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
    }
    
    private func spawnWord(_ text: String) {
        let pos = getSafePosition()
        let word = FloatingWord(text: text, position: pos, sourceContext: "vision")
        withAnimation(.easeOut(duration: 0.5)) {
            self.floatingWords.append(word)
            self.activeWordTexts.insert(text)
        }
        
        // Trigger first words callback once
        if !hasShownFirstWords {
            hasShownFirstWords = true
            onFirstWordsAppeared?()
        }
    }
    
    private func getSafePosition() -> CGPoint {
        for _ in 0..<20 {
            let p = CGPoint(x: CGFloat.random(in: 0.1...0.9), y: CGFloat.random(in: 0.15...AppConfig.floatingWordMaxY))
            var safe = true
            for w in floatingWords {
                if hypot(p.x - w.position.x, p.y - w.position.y) < 0.2 { safe = false; break }
            }
            if safe { return p }
        }
        return CGPoint(x: 0.5, y: 0.4)
    }
    
    private func startAnimationTimer() {
        Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { [weak self] _ in self?.updateWords() }
    }
    
    private func updateWords() {
        let now = Date()
        var nextWords: [FloatingWord] = []
        var nextTexts: Set<String> = []
        let lifespan = AppConfig.floatingWordLifespan
        let fadeInDuration = 0.4
        let fadeOutDuration = 0.6
        let usedWordFadeOutDuration = 1.5 // Slow linear fade for words used in poem
        
        for var w in floatingWords {
            let age = now.timeIntervalSince(w.createdAt)
            
            // Words marked for fade out (used in poem) - slow linear fade
            if w.isFadingOut {
                if let fadeStart = w.fadeOutStartTime {
                    let fadeAge = now.timeIntervalSince(fadeStart)
                    w.opacity = max(0, 1.0 - (fadeAge / usedWordFadeOutDuration))
                    if fadeAge < usedWordFadeOutDuration {
                        nextWords.append(w)
                        nextTexts.insert(w.text)
                    } else {
                        // Fully faded - remove from active texts
                        activeWordTexts.remove(w.text)
                    }
                }
                continue
            }
            
            // Selected words stay fully visible and don't expire
            if w.isSelected {
                w.opacity = 1.0
                w.scale = 1.0
                nextWords.append(w)
                nextTexts.insert(w.text)
                continue
            }
            
            // Normal words fade in/out and expire
            if age < fadeInDuration {
                w.opacity = age / fadeInDuration
                w.scale = 0.5 + (age / fadeInDuration) * 0.5
            } else if age > lifespan - fadeOutDuration {
                w.opacity = max(0, (lifespan - age) / fadeOutDuration)
            } else {
                w.opacity = 1.0
                w.scale = 1.0
            }
            
            if age < lifespan {
                nextWords.append(w)
                nextTexts.insert(w.text)
            }
        }
        self.floatingWords = nextWords
        self.activeWordTexts = nextTexts
    }
    
    private func setupCamera() {
        captureSession.sessionPreset = .high
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else { return }
        if captureSession.canAddInput(input) { captureSession.addInput(input) }
        
        captureSession.addOutput(videoOutput)
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        videoOutput.connection(with: .video)?.videoOrientation = .portrait
        
        if let mic = AVCaptureDevice.default(for: .audio), let micInput = try? AVCaptureDeviceInput(device: mic), captureSession.canAddInput(micInput) {
            captureSession.addInput(micInput)
            captureSession.addOutput(audioOutput)
        }
        
        DispatchQueue.global().async { self.captureSession.startRunning() }
    }
    
    func attachRecorder(_ recorder: RecorderService) {
        self.recorderService = recorder
        recorder.arManager = self
    }
}
















