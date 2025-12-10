import Foundation
import AVFoundation
import Photos
import Combine
import UIKit

class RecorderService: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var error: String?
    
    // References
    weak var arManager: ARManager?
    weak var poetryViewModel: PoetryViewModel?
    var onVideoSaved: (() -> Void)?
    
    // AVFoundation recording
    private var videoWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var videoOutputURL: URL?
    private var isWritingStarted = false
    
    private var recordingTimer: Timer?
    private var startTime: Date?
    
    // Reusable CI context for performance
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // Cursor blink state for video
    private var cursorVisible = true
    private var lastCursorToggle: TimeInterval = 0
    
    override init() {
        super.init()
        print("🎬 RecorderService initialized")
    }
    
    var canRecord: Bool { true }
    
    // MARK: Recording Control
    func startRecording() {
        guard !isRecording else { return }
        
        print("🎬 Starting recording...")
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoName = "pov_\(Int(Date().timeIntervalSince1970)).mp4"
        videoOutputURL = documentsPath.appendingPathComponent(videoName)
        
        if let url = videoOutputURL { try? FileManager.default.removeItem(at: url) }
        
        guard setupVideoWriter() else {
            error = "Failed to setup video writer"
            return
        }
        
        isRecording = true
        isWritingStarted = false
        startTime = Date()
        startTimer()
        
        print("🎬 Recording started")
    }
    
    func stopRecording() {
        guard isRecording else { return }
        print("🎬 Stopping recording...")
        stopTimer()
        isRecording = false
        finishWriting()
    }
    
    // MARK: Setup Writer
    private func setupVideoWriter() -> Bool {
        guard let url = videoOutputURL else { return false }
        
        do {
            videoWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
            
            // Portrait video: 1080x1920
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1080,
                AVVideoHeightKey: 1920,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            self.videoInput = videoInput
            
            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 1080,
                kCVPixelBufferHeightKey as String: 1920
            ]
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )
            
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            self.audioInput = audioInput
            
            if let writer = videoWriter {
                if writer.canAdd(videoInput) { writer.add(videoInput) }
                if writer.canAdd(audioInput) { writer.add(audioInput) }
            }
            
            return true
        } catch {
            print("❌ Failed to create video writer: \(error)")
            return false
        }
    }
    
    // MARK: Frame Processing (called from ARManager)
    func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              let writer = videoWriter,
              let input = videoInput,
              let adaptor = pixelBufferAdaptor else { return }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        if !isWritingStarted {
            writer.startWriting()
            writer.startSession(atSourceTime: timestamp)
            isWritingStarted = true
            print("🎬 Video writing session started")
        }
        
        guard writer.status == .writing, input.isReadyForMoreMediaData else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Update cursor blink (every 0.5 seconds)
        let currentTime = CACurrentMediaTime()
        if currentTime - lastCursorToggle > 0.5 {
            cursorVisible.toggle()
            lastCursorToggle = currentTime
        }
        
        let composited = compositeOverlayOnFrame(imageBuffer)
        adaptor.append(composited, withPresentationTime: timestamp)
    }
    
    // MARK: Compositing - Match PoetryOverlayView exactly
    private func compositeOverlayOnFrame(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
        guard let adaptor = pixelBufferAdaptor,
              let pool = adaptor.pixelBufferPool else { return pixelBuffer }
        
        var outputBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
        guard let output = outputBuffer else { return pixelBuffer }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(output, [])
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(output),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(output),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return pixelBuffer }
        
        // Draw original camera frame
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        
        // Transform context from CG coordinates to UIKit coordinates
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        
        UIGraphicsPushContext(context)
        
        // Scale factor: video is 1080x1920, UI is ~390x844 (iPhone 14 Pro)
        // Use 2.77x scale (1080/390 ≈ 2.77)
        let scale: CGFloat = CGFloat(width) / 390.0
        
        // Draw floating words + kept words
        if let manager = arManager {
            let allWords = manager.floatingWords + manager.keptWords
            for word in allWords {
                let x = word.position.x * CGFloat(width)
                let y = word.position.y * CGFloat(height)
                
                let isKept = manager.keptWords.contains(where: { $0.id == word.id })
                let fontSize: CGFloat = (isKept ? 20 : 18) * scale
                
                let font = UIFont(name: "PingFangSC-Semibold", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize, weight: .semibold)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.white
                ]
                
                let text = word.text as NSString
                let textSize = text.size(withAttributes: attributes)
                
                text.draw(
                    at: CGPoint(x: x - textSize.width/2, y: y - textSize.height/2),
                    withAttributes: attributes
                )
            }
        }
        
        // Draw poetry overlay - matching PoetryOverlayView exactly
        drawPoetryOverlay(context: context, width: width, height: height, scale: scale)
        
        UIGraphicsPopContext()
        
        return output
    }
    
    // MARK: Poetry Rendering - Matches PoetryOverlayView
    private func drawPoetryOverlay(context: CGContext, width: Int, height: Int, scale: CGFloat) {
        guard let poetry = poetryViewModel else { return }
        
        let lines = poetry.poemLines
        let currentTypingText = poetry.currentTypingText
        let isTyping = poetry.isTyping
        
        // Skip if nothing to draw
        guard !lines.isEmpty || !currentTypingText.isEmpty || isTyping else { return }
        
        // Padding matching SwiftUI (24 horizontal, 16 vertical)
        let horizontalPadding: CGFloat = 24 * scale
        let verticalPadding: CGFloat = 16 * scale
        let lineSpacing: CGFloat = 8 * scale
        
        // Fonts matching PoetryOverlayView
        let historyFont = UIFont(name: "PingFangSC-Light", size: 16 * scale) ?? UIFont.systemFont(ofSize: 16 * scale, weight: .light)
        let typingFont = UIFont(name: "PingFangSC-Regular", size: 18 * scale) ?? UIFont.systemFont(ofSize: 18 * scale, weight: .regular)
        
        // Calculate total content height
        var totalHeight: CGFloat = 0
        var lineHeights: [CGFloat] = []
        
        for (index, line) in lines.enumerated() {
            let opacity: CGFloat = (index == lines.count - 1) ? 0.9 : 0.6
            let attributes: [NSAttributedString.Key: Any] = [
                .font: historyFont,
                .foregroundColor: UIColor.white.withAlphaComponent(opacity)
            ]
            let size = (line.text as NSString).size(withAttributes: attributes)
            lineHeights.append(size.height)
            totalHeight += size.height + (index > 0 ? lineSpacing : 0)
        }
        
        // Current typing line
        var typingLineHeight: CGFloat = 0
        if !currentTypingText.isEmpty || isTyping {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: typingFont,
                .foregroundColor: UIColor.white
            ]
            let displayText = currentTypingText + (isTyping && cursorVisible ? "|" : "")
            let size = (displayText as NSString).size(withAttributes: attributes)
            typingLineHeight = size.height
            if !lines.isEmpty {
                totalHeight += lineSpacing
            }
            totalHeight += typingLineHeight
        }
        
        // Background gradient area (bottom of screen)
        let bgHeight = totalHeight + verticalPadding * 2
        let bgY = CGFloat(height) - bgHeight
        
        // Draw gradient background
        let gradientColors = [
            UIColor.black.withAlphaComponent(0.0).cgColor,
            UIColor.black.withAlphaComponent(0.4).cgColor,
            UIColor.black.withAlphaComponent(0.6).cgColor
        ]
        let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors as CFArray, locations: [0, 0.5, 1])!
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: bgY, width: CGFloat(width), height: bgHeight))
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: bgY), end: CGPoint(x: 0, y: CGFloat(height)), options: [])
        context.restoreGState()
        
        // Draw lines from top to bottom within the poetry area
        var currentY = bgY + verticalPadding
        
        for (index, line) in lines.enumerated() {
            let opacity: CGFloat = (index == lines.count - 1) ? 0.9 : 0.6
            let attributes: [NSAttributedString.Key: Any] = [
                .font: historyFont,
                .foregroundColor: UIColor.white.withAlphaComponent(opacity)
            ]
            let text = line.text as NSString
            let size = text.size(withAttributes: attributes)
            
            // Center horizontally
            let x = (CGFloat(width) - size.width) / 2
            text.draw(at: CGPoint(x: x, y: currentY), withAttributes: attributes)
            
            currentY += size.height + lineSpacing
        }
        
        // Draw current typing line
        if !currentTypingText.isEmpty || isTyping {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: typingFont,
                .foregroundColor: UIColor.white
            ]
            let displayText = currentTypingText + (isTyping && cursorVisible ? "|" : "")
            let text = displayText as NSString
            let size = text.size(withAttributes: attributes)
            
            // Center horizontally
            let x = (CGFloat(width) - size.width) / 2
            text.draw(at: CGPoint(x: x, y: currentY), withAttributes: attributes)
        }
    }
    
    private var colorSpace: CGColorSpace {
        CGColorSpaceCreateDeviceRGB()
    }
    
    // MARK: Finish Writing
    private func finishWriting() {
        guard let writer = videoWriter else {
            print("❌ No video writer")
            return
        }
        
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        
        writer.finishWriting { [weak self] in
            guard let self = self, let url = self.videoOutputURL else { return }
            
            DispatchQueue.main.async {
                if writer.status == .completed {
                    print("🎬 Video saved to: \(url)")
                    self.saveToPhotoLibrary(url: url)
                } else if let error = writer.error {
                    print("❌ Video writing failed: \(error)")
                    self.error = error.localizedDescription
                }
                
                self.videoWriter = nil
                self.videoInput = nil
                self.audioInput = nil
                self.pixelBufferAdaptor = nil
                self.isWritingStarted = false
            }
        }
    }
    
    // MARK: Save
    private func saveToPhotoLibrary(url: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self.error = "Photo library access denied" }
                return
            }
            
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("🎬 Video saved to Photo Library!")
                        try? FileManager.default.removeItem(at: url)
                        self.onVideoSaved?()
                    } else if let error = error {
                        print("❌ Failed to save to Photo Library: \(error)")
                        self.error = error.localizedDescription
                    }
                }
            }
        }
    }
    
    // MARK: Timer
    private func startTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let startTime = self?.startTime else { return }
            self?.recordingDuration = Date().timeIntervalSince(startTime)
        }
    }
    
    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0
    }
}

// MARK: - Audio Delegate
extension RecorderService: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isRecording,
              isWritingStarted,
              let writer = videoWriter,
              writer.status == .writing,
              let input = audioInput,
              input.isReadyForMoreMediaData else { return }
        
        input.append(sampleBuffer)
    }
}
